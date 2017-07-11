/*
 * Copyright 2017 Hortonworks, Inc.
 * All rights reserved.
 *
 *   Hortonworks, Inc. licenses this file to you under the Apache License, Version 2.0
 *   (the "License"); you may not use this file except in compliance with
 *   the License. You may obtain a copy of the License at
 *   http://www.apache.org/licenses/LICENSE-2.0
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 *
 * See the associated NOTICE file for additional information regarding copyright ownership.
 */

#import <Foundation/Foundation.h>
#import "NiFiHttpSiteToSiteClient.h"

NSString *const HTTP_SITE_TO_SITE_PROTOCOL_VERSION = @"5";

typedef void(^TtlExtenderBlock)(NSString * transactionId);


@implementation NiFiHttpTransaction

- (nonnull instancetype) initWithPortId:(nonnull NSString *)portId
                      httpRestApiClient:(NiFiHttpRestApiClient *)restApiClient {
    self = [super init];
    if(self != nil) {
        _restApiClient = restApiClient;
        NSError *error;
        _transactionResource = [_restApiClient initiateSendTransactionToPortId:portId error:&error];
        if (_transactionResource) {
            _startTime = [NSDate date];
            _transactionState = TRANSACTION_STARTED;
            _shouldKeepAlive = true;
            [self scheduleNextKeepAliveWithTTL:(_transactionResource.serverSideTtl)];
            _dataPacketEncoder = [[NiFiDataPacketEncoder alloc] init];
        } else {
            NSLog(@"ERROR  %@", [error localizedDescription]);
            self = nil;
        }
    }
    return self;
}

- (NSString *)transactionId {
    return _transactionResource.transactionId;
}

- (void) sendData:(NiFiDataPacket *)data {
    [_dataPacketEncoder appendDataPacket:data];
    _transactionState = DATA_EXCHANGED;
}

- (void) cancel {
    [self cancelWithExplaination:@""];
}

- (void) cancelWithExplaination: (nonnull NSString *)explaination {
    NSError *error;
    _transactionState = TRANSACTION_CANCELED;
    _shouldKeepAlive = false;
    [_restApiClient endTransaction:_transactionResource.transactionUrl responseCode:CANCEL_TRANSACTION error:&error];
}

- (void) error {
    _transactionState = TRANSACTION_ERROR;
    _shouldKeepAlive = false;
}

- (nullable NiFiTransactionResult *)confirmAndCompleteOrError:(NSError *_Nullable *_Nullable)error {
    [self confirmOrError:error];
    if (error && *error) {
        return nil;
    } else {
        return [self completeOrError:error];
    }
}

- (void) confirmOrError:(NSError *_Nullable *_Nullable)error {
    NSUInteger serverCrc = [_restApiClient sendFlowFiles:_dataPacketEncoder
                                         withTransaction:_transactionResource
                                                   error:error];
    
    NSUInteger expectedCrc = [_dataPacketEncoder getEncodedDataCrcChecksum];
    
    NSLog(@"NiFi Peer returned CRC code: %ld, expected CRC was: %ld", (unsigned long)serverCrc, (unsigned long)expectedCrc);
    
    if (serverCrc != expectedCrc) {
        [_restApiClient endTransaction:_transactionResource.transactionUrl responseCode:BAD_CHECKSUM error:error];
        [self error];
    }
    else {
        _transactionState = TRANSACTION_CONFIRMED;
        // The endTransaction communication to server is sent from the complete() function
    }
}

- (nullable NiFiTransactionResult *)completeOrError:(NSError *_Nullable *_Nullable)error {
    // Must be called after confirm interacton is done.
    if (![[self class] assertExpectedState:TRANSACTION_CONFIRMED equalsActualState:_transactionState]) {
        [self error];
    }
    
    NiFiTransactionResult *transactionResult = [_restApiClient endTransaction:_transactionResource.transactionUrl
                                                                 responseCode:CONFIRM_TRANSACTION
                                                                        error:error];
    if (error && *error) {
        [self error];
        return nil;
    } else {
        _transactionState = TRANSACTION_COMPLETED;
        transactionResult.duration = [[NSDate date] timeIntervalSinceDate:_startTime];
        _shouldKeepAlive = false;
        return transactionResult;
    }
}



- (nullable NSObject <NiFiCommunicant> *)getCommunicant {
    return [[NiFiPeer alloc] initWithUrl:[_restApiClient baseUrl]];
}

- (nullable NiFiDataPacket *)receive {
    @throw [NSException
            exceptionWithName:NSInternalInconsistencyException
            reason:[NSString stringWithFormat:@"%@ is not implemented is send-only transaction type", NSStringFromSelector(_cmd)]
            userInfo:nil];
}

- (void)scheduleNextKeepAliveWithTTL:(NSTimeInterval)ttl {
    // schedule another keep alive if needed
    if (_shouldKeepAlive) {
        NSLog(@"Scheduling background task to extend transaction TTL");
        dispatch_time_t nextKeepAlive = dispatch_time(DISPATCH_TIME_NOW, (ttl / 2) * NSEC_PER_SEC);
        dispatch_after(nextKeepAlive, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(void){
            if (self &&
                    [self shouldKeepAlive] &&
                    [self restApiClient] &&
                    [self transactionResource] &&
                    [self transactionResource].transactionUrl) {
                [_restApiClient extendTTLForTransaction:_transactionResource.transactionUrl error:nil];
                [self scheduleNextKeepAliveWithTTL:ttl]; // this will put the next "keep-alive heartbeat" task on an async queue
            }
        });
    }
}

+ (bool)assertExpectedState:(NiFiTransactionState)expectedState equalsActualState:(NiFiTransactionState)actualState {
    if (expectedState != actualState) {
        NSLog(@"NiFiTransaction encountered internal state error. Expected to be in state %@, actually in state %@",
              [NiFiUtil NiFiTransactionStateToString:expectedState],
              [NiFiUtil NiFiTransactionStateToString:actualState]);
        return false;
    }
    return true;
}

@end


@implementation NiFiHttpSiteToSiteClient

- (nonnull instancetype) initWithConfig:(nonnull NiFiSiteToSiteClientConfig *)config {
    self = [super initWithConfig:config];
    if(self != nil) {
        // additional initialization specific to HTTP concrete class
    }
    return self;
}

- (nullable NSObject <NiFiTransaction> *)createTransaction {
    NSURLSession *urlSession;
    if (self.config.urlSessionConfiguration || self.config.urlSessionDelegate) {
        urlSession = [NSURLSession sessionWithConfiguration:self.config.urlSessionConfiguration ?: [NSURLSessionConfiguration defaultSessionConfiguration]
                                                   delegate:self.config.urlSessionDelegate
                                              delegateQueue:nil];
    } else {
        urlSession = [NSURLSession sharedSession];
    }
    
    return [self createTransactionWithURLSession:urlSession];
}

- (nullable NSObject <NiFiTransaction> *)createTransactionWithURLSession:(NSURLSession *)urlSession {
    NSURLComponents *apiBaseUrlComponents = [[NSURLComponents alloc] init];
    apiBaseUrlComponents.scheme = super.config.secure ? @"https" : @"http";
    apiBaseUrlComponents.host = super.config.host;
    apiBaseUrlComponents.port = super.config.port;
    
    NSURLCredential *credential = nil;
    if (super.config.secure && super.config.username && super.config.password) {
        credential = [NSURLCredential credentialWithUser:super.config.username
                                                password:super.config.password
                                             persistence:NSURLCredentialPersistenceForSession];
    }
    
    NiFiHttpRestApiClient *restApiClient = [[NiFiHttpRestApiClient alloc] initWithBaseUrl:apiBaseUrlComponents.URL
                                                                         clientCredential:credential
                                                                               urlSession:(NSObject<NSURLSessionProtocol> *)urlSession];
    
    NiFiHttpTransaction *transaction = nil;
    if (super.config.portId) {
        transaction = [[NiFiHttpTransaction alloc] initWithPortId:super.config.portId httpRestApiClient:restApiClient];
    }
    
    if (!transaction && super.config.portName) { // if we don't have port id, or if init by port id failed, try init by name.
        NSError *portIdLookupError;
        NSString *portId = [restApiClient getPortIdForPortName:super.config.portName error:&portIdLookupError];
        if (portIdLookupError || portId == nil) {
            NSLog(@"When looking up port ID by name, encountered error with domain=%@, code=%ld, message=%@",
                  portIdLookupError.domain,
                  (long)portIdLookupError.code,
                  portIdLookupError.localizedDescription);
            return nil;
        } else {
            NSLog(@"Discovered portId '%@' for input port named '%@'. Using that port for site-to-site transaction.", portId, super.config.portName);
            super.config.portId = portId; // cache this in this client config so we don't have to look it up again.
            transaction = [[NiFiHttpTransaction alloc] initWithPortId:portId httpRestApiClient:restApiClient];
        }
    } else {
        NSLog(@"Could not create NiFi s2s transaction. Check NiFi s2s configuration. "
              "Is the correct host, port, and s2s portName/portId set?");
    }
    return transaction;
}

@end
