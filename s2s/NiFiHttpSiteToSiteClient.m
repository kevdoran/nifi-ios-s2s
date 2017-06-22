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

static const int SECONDS_TO_NANOS = 1000000000;
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

- (nonnull NiFiTransactionResult *) confirmAndComplete {
    [self confirm];
    return [self complete];
}

- (void) confirm {
    /** TODO evaluate: The usage of a data encoder as a collector for "sent" data packets is potentially suboptimal if
     ** there is a significant ammount of time between the first send() and call to confirm(), during which we could
     ** have started transmitting data.
     **
     ** On Apple's iOS platform it is nontrivial to open an output stream for an HTTP POST body binary stream.
     ** Essentially, there is no iOS Core Framework equivalent for Java's HttpURLConnection getOutputStream().
     ** One possible improvement for would be by implementing something like a bound stream pair:
     **   https://stackoverflow.com/questions/18348863/ios-how-to-upload-a-large-asset-file-into-sever-by-streaming
     ** Another possibility would be to build a custom HTTP client implementation on top of raw sockets :-|
     **
     ** This is only suboptimal in the case of non-queued transmission. In the case of queuing to a local repository
     ** or database, and transmission in batch processing of the queue, the approach used in the ccerent implementation
     ** has no downside. The only downside would be long-lived transactions without queuing, where the data transmission
     ** time incurred at confirmation time would be significant. Even in that case... holding open a long-lived http
     ** connection has potential for failure, especially on mobile devices (perhaps this is why iOS networking
     ** APIs are opinionated in their design to make this difficult).
     **/
    NSError *error;
    NSUInteger serverCrc = [_restApiClient sendFlowFiles:_dataPacketEncoder
                                         withTransaction:_transactionResource
                                                   error:&error];
    NSUInteger expectedCrc = [_dataPacketEncoder getEncodedDataCrcChecksum];
    
    NSLog(@"NiFi Peer returned CRC code: %ld, expected CRC was: %ld", (unsigned long)serverCrc, (unsigned long)expectedCrc);
    
    if (serverCrc != expectedCrc) {
        _transactionState = TRANSACTION_ERROR;
        _shouldKeepAlive = false;
        [_restApiClient endTransaction:_transactionResource.transactionUrl responseCode:BAD_CHECKSUM error:&error];
    }
    else {
        _transactionState = TRANSACTION_CONFIRMED;
        // The endTransaction communication to server is sent from the complete() function
    }
}

- (nonnull NiFiTransactionResult *)complete {
    NSError *error;
    NiFiTransactionResult *transactionResult = [_restApiClient endTransaction:_transactionResource.transactionUrl
                                                                 responseCode:CONFIRM_TRANSACTION
                                                                        error:&error];
    _transactionState = TRANSACTION_COMPLETED;
    
    transactionResult.duration = [[NSDate date] timeIntervalSinceDate:_startTime];
    _shouldKeepAlive = false;
    
    return transactionResult;
}



- (nonnull NSObject <NiFiCommunicant> *)getCommunicant {
    return [[NiFiPeer alloc] initWithUrl:[_restApiClient baseUrl]];
}

- (nullable NiFiDataPacket *)receive {
    @throw [NSException
            exceptionWithName:NSInternalInconsistencyException
            reason:[NSString stringWithFormat:@"%@ is not implemented is send-only transaction type", NSStringFromSelector(_cmd)]
            userInfo:nil];
}

- (void) scheduleNextKeepAliveWithTTL:(NSTimeInterval)ttl {
    // schedule another keep alive if needed
    if (_shouldKeepAlive) {
        NSLog(@"Scheduling background task to extend transaction TTL");
        dispatch_time_t nextKeepAlive = dispatch_time(DISPATCH_TIME_NOW, (ttl / 2) * SECONDS_TO_NANOS);
        dispatch_after(nextKeepAlive, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(void){
            if (self &&
                    [self shouldKeepAlive] &&
                    [self restApiClient] &&
                    [self transactionResource] &&
                    [self transactionResource].transactionUrl) {
                [_restApiClient extendTTLForTransaction:_transactionResource.transactionUrl error:nil];
            }
            [self scheduleNextKeepAliveWithTTL:ttl]; // this will put the next "keep-alive heartbeat" task on an async queue
        });
    }
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

- (nonnull NSObject <NiFiTransaction> *)createTransaction {
    return [self createTransactionWithURLSession:[NSURLSession sharedSession]];
}

- (nonnull NSObject <NiFiTransaction> *)createTransactionWithURLSession:(NSURLSession *)urlSession {
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
    return [[NiFiHttpTransaction alloc] initWithPortId:super.config.portId httpRestApiClient:restApiClient];
}

- (bool)isSecure {
    @throw [NSException
            exceptionWithName:NSInternalInconsistencyException
            reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
            userInfo:nil];
}

@end
