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
#import "NiFiSiteToSite.h"
#import "NiFiSiteToSiteClient.h"
#import "NiFiHttpRestApiClient.h"

// MARK: - SiteToSite Internal Interface Extentensions

@interface NiFiSiteToSiteClient()
@property (nonatomic, retain, readwrite, nonnull) NiFiSiteToSiteClientConfig *config;
- (nonnull instancetype) initWithConfig:(nonnull NiFiSiteToSiteClientConfig *)config;
@end


// An abstract base class for clients that want to implement a client for a given protocol to a given cluster
@interface NiFiSiteToSiteUniClusterClient : NiFiSiteToSiteClient
@property (nonatomic, retain, readwrite, nonnull) NiFiSiteToSiteRemoteClusterConfig *remoteClusterConfig;
@property (nonatomic, readwrite, nullable)NSArray *prioritizedRemoteInputPortIdList;
@property (atomic, readwrite, nonnull)NSSet *initialPeerKeySet; // key of every peer in initial config
@property (atomic, readwrite, nonnull)NSArray<NiFiPeer *> *currentPeerList;
- (nullable instancetype) initWithConfig:(nonnull NiFiSiteToSiteClientConfig *)config
                          remoteCluster:(nonnull NiFiSiteToSiteRemoteClusterConfig *)remoteClusterConfig;
@end


@interface NiFiHttpSiteToSiteClient : NiFiSiteToSiteUniClusterClient
@end


// MARK: - TransactionResult Implementation

@implementation NiFiTransactionResult

- (nonnull instancetype)init {
    return [self initWithResponseCode:RESERVED dataPacketsTransferred:0 message:nil duration:0];
}

- (nonnull instancetype)initWithResponseCode:(NiFiTransactionResponseCode)responseCode
                      dataPacketsTransferred:(NSUInteger)packetCount
                                     message:(NSString *)message
                                    duration:(NSTimeInterval)duration {
    self = [super init];
    if(self != nil) {
        _responseCode = responseCode;
        _dataPacketsTransferred = packetCount;
        _message = message;
        _duration = duration;
    }
    return self;
}

- (bool)shouldBackoff {
    return _responseCode == TRANSACTION_FINISHED_BUT_DESTINATION_FULL;
}

@end



// MARK: - SiteToSiteMultiClusterClient Implementation

@interface NiFiSiteToSiteMultiClusterClient : NiFiSiteToSiteClient
@property (nonatomic, retain, readwrite, nonnull) NSMutableArray *clusterClients;
- (nullable NSObject <NiFiTransaction> *)createTransactionWithURLSession:(nullable NSURLSession *)urlSession; // redefining nullability
@end


@implementation NiFiSiteToSiteMultiClusterClient

+ (nonnull instancetype) clientWithConfig:(nonnull NiFiSiteToSiteClientConfig *)config {
    if (config && config.remoteClusters && [config.remoteClusters count] > 0) {
        return [[self alloc] initWithConfig:config];
    }
    NSLog(@"No remote clusters configured!");
    return nil;
}

- (instancetype)initWithConfig:(NiFiSiteToSiteClientConfig *)config {
    self = [super initWithConfig:config];
    if (self) {
        [self createClients];
    }
    return self;
}

- (void)createClients {
    _clusterClients = [NSMutableArray arrayWithCapacity:[self.config.remoteClusters count]];
    for (NiFiSiteToSiteRemoteClusterConfig *clusterConfig in self.config.remoteClusters) {
        NiFiSiteToSiteClient *client = nil;
        
        switch (clusterConfig.transportProtocol) {
            case HTTP:
                client = [[NiFiHttpSiteToSiteClient alloc] initWithConfig:self.config remoteCluster:clusterConfig];
                break;
            default:
                @throw [NSException
                        exceptionWithName:NSGenericException
                        reason:@"Unsupported NiFiSiteToSiteTransportProtocol when creating NiFiSiteToSiteClient."
                        userInfo:nil];
        }
        
        if (client) {
            [_clusterClients addObject:client];
        }
    }
}

- (nullable NSObject <NiFiTransaction> *)createTransaction {
    return [self createTransactionWithURLSession:nil];
}

- (nullable NSObject <NiFiTransaction> *)createTransactionWithURLSession:(NSURLSession *)urlSession {
    for (NiFiSiteToSiteClient *client in _clusterClients) {
        id transaction = urlSession ? [client createTransactionWithURLSession:urlSession] : [client createTransaction];
        if (transaction) {
            return transaction;
        }
    }
    return nil;
}

@end



// MARK: - SiteToSiteClient Implementation

@implementation NiFiSiteToSiteClient

+ (nonnull instancetype) clientWithConfig:(nonnull NiFiSiteToSiteClientConfig *)config {
    return [NiFiSiteToSiteMultiClusterClient clientWithConfig:config];
}

- (nonnull instancetype) initWithConfig:(nonnull NiFiSiteToSiteClientConfig *) config {
    self = [super init];
    if(self != nil) {
        _config = config;
    }
    return self;
}

- (nullable NSObject <NiFiTransaction> *)createTransaction {
    @throw [NSException
            exceptionWithName:NSInternalInconsistencyException
            reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
            userInfo:nil];
}

- (nullable NSObject <NiFiTransaction> *)createTransactionWithURLSession:(NSURLSession *)urlSession {
    @throw [NSException
            exceptionWithName:NSInternalInconsistencyException
            reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
            userInfo:nil];
}

@end



// MARK: - SiteToSiteUniClusterClient Implementation

@implementation NiFiSiteToSiteUniClusterClient
- (nullable instancetype) initWithConfig:(nonnull NiFiSiteToSiteClientConfig *)config
                          remoteCluster:(nonnull NiFiSiteToSiteRemoteClusterConfig *)remoteClusterConfig {
    self = [super initWithConfig:config];
    if (self) {
        _remoteClusterConfig = remoteClusterConfig;
        [self resetPeersFromInitialPeerConfig];
        if (! _currentPeerList || _currentPeerList.count <= 0) {
            self = nil;
        }
        if (self.config.peerUpdateInterval > 0.0) {
            // starts background peer refresh, initial delay is zero, repeating delay will come from config.
            [self scheduleNextPeerUpdateWithDelay:0.0];
        }
    }
    return self;
}

- (nullable NSObject <NiFiTransaction> *)createTransaction {
    return [self createTransactionWithURLSession:[self createUrlSession]];
}

// This is an abstract class. createTransactionWithURLSession:urlSession must be implemented by subclass

- (nullable NiFiPeer *)getPreferredPeer {
    NSArray *sortedPeerList = [self getSortedPeerList];
    // TODO, for large clusters, sort is non-trivial computation expense, so we should cache the sort result
    if (!sortedPeerList) {
        return nil;
    }
    return sortedPeerList[0];
}

- (NSArray<NiFiPeer *> *)getSortedPeerList {
    if (!_currentPeerList) {
        return nil;
    }
    NSArray *sortedPeerList = [_currentPeerList sortedArrayUsingSelector:@selector(compare:)];
    return sortedPeerList;
}

- (void)resetPeersFromInitialPeerConfig {
    if (_remoteClusterConfig.urls && _remoteClusterConfig.urls.count > 0) {
        _currentPeerList = [NSMutableArray arrayWithCapacity:_remoteClusterConfig.urls.count];
        _initialPeerKeySet = [NSMutableSet setWithCapacity:_remoteClusterConfig.urls.count];
        for (NSURL *url in _remoteClusterConfig.urls) {
            NiFiPeer *peer = [NiFiPeer peerWithUrl:url];
            if (peer) {
                [(NSMutableArray *)_currentPeerList addObject:peer];
                [(NSMutableSet *)_initialPeerKeySet addObject:[peer peerKey]];
            }
        }
    }
}

- (void)updatePeers {
    NSURLSession *urlSession = [self createUrlSession];
    if (! _currentPeerList || _currentPeerList.count < 1) {
        [self resetPeersFromInitialPeerConfig];
    }
    for (NiFiPeer *peer in _currentPeerList) {
        NiFiHttpRestApiClient *apiClient = [self createRestApiClientWithBaseUrl:peer.url
                                                                     urlSession:(NSObject<NSURLSessionProtocol> *)urlSession];
        NSArray *newPeers = [apiClient getPeersOrError:nil];
        if (newPeers) {
            [self addPeers:newPeers];
            NSLog(@"Successfully updated peers for remote NiFi cluster.");
            return; // done
        }
    }
    NSLog(@"Error: Failed to update peers for remote NiFi cluster.");
}

- (void)addPeers:(NSArray<NiFiPeer *> *)newPeerList {
    NSMutableDictionary<NSURL *, NiFiPeer *> *newPeerMap = [NSMutableDictionary dictionaryWithCapacity:[newPeerList count]];
    for (NiFiPeer *peer in newPeerList) {
        id newPeerKey = [peer.url absoluteURL];
        [newPeerMap setObject:peer forKey:newPeerKey];
    }
    for (NiFiPeer *peer in _currentPeerList) {
        id oldPeerKey = [peer.url absoluteURL];
        if (newPeerMap[oldPeerKey]) {
            newPeerMap[oldPeerKey].lastFailure = peer.lastFailure;
        } else if ([_initialPeerKeySet containsObject:oldPeerKey]) {
            [newPeerMap setObject:peer forKey:oldPeerKey];
        }
    }
    if (newPeerMap && newPeerMap.count > 0) {
        _currentPeerList = [newPeerMap allValues];
    }
}

- (void)scheduleNextPeerUpdateWithDelay:(NSTimeInterval)delay {
    NSLog(@"Scheduling background task to update peer list.");
    // TODO, instead of dispatch_after, look into if a serial queue or NSOperationsQueue would be more appropriate,
    // especially for small refresh intervals. Alternatively could just do this lazily on demand when createTransaction is called.
    dispatch_time_t nextPeerUpdate = dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC);
    dispatch_after(nextPeerUpdate, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^(void){
        if (self) {
            [self updatePeers];
        }
        if (self.config.peerUpdateInterval > 0.0) {
            // this will put the next peer update task on an async queue
            [self scheduleNextPeerUpdateWithDelay:self.config.peerUpdateInterval];
        }
    });
}

// MARK: Helper functions 

- (NSURLSession *)createUrlSession {
    NSURLSession *urlSession;
    if (self.remoteClusterConfig.urlSessionConfiguration || self.remoteClusterConfig.urlSessionDelegate) {
        NSURLSessionConfiguration *configuration = self.remoteClusterConfig.urlSessionConfiguration ?: [NSURLSessionConfiguration defaultSessionConfiguration];
        urlSession = [NSURLSession sessionWithConfiguration:configuration
                                                   delegate:self.remoteClusterConfig.urlSessionDelegate
                                              delegateQueue:nil];
    } else {
        urlSession = [NSURLSession sharedSession];
    }
    return urlSession;
}

- (NiFiHttpRestApiClient *)createRestApiClientWithBaseUrl:(NSURL *)url
                                               urlSession:(NSObject<NSURLSessionProtocol> *)urlSession {
    
    /* strip path component of url if one was passed */
    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!urlComponents) {
        NSLog(@"Invalid url '%@' for remote cluster could not be parsed.", url);
    }
    urlComponents.path = nil; // REST API Client constructor expects base url.
    NSURL *apiBaseUrl = urlComponents.URL;
    
    /* create credentials if necessary */
    NSURLCredential *credential = nil;
    if (_remoteClusterConfig.username && _remoteClusterConfig.password) {
        credential = [NSURLCredential credentialWithUser:_remoteClusterConfig.username
                                                password:_remoteClusterConfig.password
                                             persistence:NSURLCredentialPersistenceForSession];
    }
    
    NiFiHttpRestApiClient *restApiClient = [[NiFiHttpRestApiClient alloc] initWithBaseUrl:apiBaseUrl
                                                                         clientCredential:credential
                                                                               urlSession:urlSession];
    
    return restApiClient;
}

- (void) updatePrioritizedPortList:(nonnull NiFiHttpRestApiClient *)restApiClient {

    NSError *portIdLookupError;
    NSDictionary *portIdsByName = [restApiClient getRemoteInputPortsOrError:&portIdLookupError];
    if (portIdLookupError || portIdsByName == nil) {
        NSString *errMsg = portIdLookupError ?
        [NSString stringWithFormat:@"When looking up port ID by name, encountered error with domain=%@, code=%ld, message=%@",
         portIdLookupError.domain,
         (long)portIdLookupError.code,
         portIdLookupError.localizedDescription] :
        @"When looking up port ID by name, encountered error";
        NSLog(@"%@", errMsg);
    }
    
    // The priority of port resolution is currently:
    //   - portID (if provided in the config)
    //   - portID for a given portName
    //   - portID if exactly 1 input port exists at the remote instance / cluster.
    NSMutableArray *prioritizedPortList = [NSMutableArray arrayWithCapacity:1];
    
    if (self.config.portId) {
        [prioritizedPortList addObject:self.config.portId];
    }
    
    if (portIdsByName) {
        if (self.config.portName) {
            NSString *portIdByName = portIdsByName[self.config.portName];
            if (portIdByName && ![prioritizedPortList containsObject:portIdsByName]) {
                [prioritizedPortList addObject:portIdByName];
            }
        }
        
        if ([portIdsByName count] == 1) {
            NSString *solePortId = [portIdsByName allValues][0];
            if (solePortId && ![prioritizedPortList containsObject:solePortId]) {
                [prioritizedPortList addObject:solePortId];
            }
        }
    }
    
    if (prioritizedPortList && [prioritizedPortList count] > 0) {
        _prioritizedRemoteInputPortIdList = prioritizedPortList;
    }
}


@end



// MARK: HttpSiteToSiteClient Implementation

NSString *const HTTP_SITE_TO_SITE_PROTOCOL_VERSION = @"5";


typedef void(^TtlExtenderBlock)(NSString * transactionId);


@implementation NiFiHttpTransaction

- (nonnull instancetype) initWithPortId:(nonnull NSString *)portId
                      httpRestApiClient:(NiFiHttpRestApiClient *)restApiClient {
    return [self initWithPortId:portId httpRestApiClient:restApiClient peer:nil];
}

- (nonnull instancetype) initWithPortId:(nonnull NSString *)portId
                      httpRestApiClient:(nonnull NiFiHttpRestApiClient *)restApiClient
                                   peer:(nullable NiFiPeer *)peer {
    self = [super init];
    if(self != nil) {
        _restApiClient = restApiClient;
        _peer = peer;
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
    if (_peer) {
        [_peer markFailure];
    }
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

- (nullable NiFiPeer *)getCommunicant {
    NiFiPeer *peer = [NiFiPeer peerWithUrl:[_restApiClient baseUrl]];
    return peer;
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
              [NiFiSiteToSiteUtil NiFiTransactionStateToString:expectedState],
              [NiFiSiteToSiteUtil NiFiTransactionStateToString:actualState]);
        return false;
    }
    return true;
}

@end


@implementation NiFiHttpSiteToSiteClient

- (nullable NSObject <NiFiTransaction> *)createTransactionWithURLSession:(NSURLSession *)urlSession {
    NiFiPeer *peer = [self getPreferredPeer];
    
    NiFiHttpRestApiClient *restApiClient = [self createRestApiClientWithBaseUrl:peer.url
                                                                     urlSession:(NSObject<NSURLSessionProtocol> *)urlSession];
    
    if (!self.prioritizedRemoteInputPortIdList) {
        [self updatePrioritizedPortList:restApiClient];
    }
    
    NiFiHttpTransaction *transaction = nil;
    if (self.prioritizedRemoteInputPortIdList) {
        for (NSString *portId in self.prioritizedRemoteInputPortIdList) {
            NSLog(@"Attempting to initiate transaction. portId=%@", portId);
            transaction = [[NiFiHttpTransaction alloc] initWithPortId:portId httpRestApiClient:restApiClient];
            if (transaction) {
                NSLog(@"Successfully initiated transaction. transactionId=%@, portId=%@",
                      transaction.transactionId, portId);
                break;
            }
        }
    }
    
    if (!transaction) {
        [peer markFailure];
        NSLog(@"Could not create NiFi s2s transaction. Check NiFi s2s configuration. "
              "Is the correct url and s2s portName/portId set?");
    }
    return transaction;
}


@end









