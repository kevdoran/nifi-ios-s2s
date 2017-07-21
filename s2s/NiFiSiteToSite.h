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

#ifndef NiFiSiteToSite_h
#define NiFiSiteToSite_h

/* Visibility: External / Public
 *
 * This header defines a public interface of the s2s framework / module.
 */

#import <Foundation/Foundation.h>


// MARK: - Enums -

typedef enum {
    HTTP,
    // RAW_SOCKET, // TODO, there is also the socket variant of the NiFi Site-to-Site protocol that could be implemented if needed
} NiFiSiteToSiteTransportProtocol;


typedef enum {
    TRANSACTION_STARTED,
    DATA_EXCHANGED,
    TRANSACTION_CONFIRMED,
    TRANSACTION_COMPLETED,
    TRANSACTION_CANCELED,
    TRANSACTION_ERROR
} NiFiTransactionState;



// MARK: - Config Classes -

@interface NiFiProxyConfig : NSObject <NSCopying>
@property (nonatomic, retain, readwrite, nonnull) NSURL *proxyUrl;   // HTTP(S) URL of proxy, required
@property (nonatomic, retain, readwrite, nullable) NSString *proxyUsername;  // optional proxy credentials for Basic Auth authenticaton
@property (nonatomic, retain, readwrite, nullable) NSString *proxyPassword;  // optional proxy credentials for Basic Auth authenticaton
+ (nullable instancetype) proxyConfigWithUrl:(nonnull NSURL *)url;
@end


@interface NiFiSiteToSiteRemoteClusterConfig : NSObject <NSCopying>
@property (nonatomic, retain, readwrite, nonnull) NSMutableSet<NSURL *> *urls;
@property (nonatomic, readwrite) NiFiSiteToSiteTransportProtocol transportProtocol;  // defaults to HTTP
@property (nonatomic, retain, readwrite, nullable) NiFiProxyConfig *proxyConfig;  // optional HTTP proxy to use to connect to remote cluster
@property (nonatomic, retain, readwrite, nullable) NSString *username;  // optional NiFi user credentials for two-way auth
@property (nonatomic, retain, readwrite, nullable) NSString *password;  // optional NiFi user credentials for two-way auth
@property (nonatomic, retain, readwrite, nullable) NSURLSessionConfiguration *urlSessionConfiguration;  // optional URLSessionConfiguration to use
@property (nonatomic, retain, readwrite, nullable) NSObject <NSURLSessionDelegate> *urlSessionDelegate;  // optional URLSessionDelegate to use
+ (nullable instancetype) configWithUrl:(nonnull NSURL *)url;
+ (nullable instancetype) configWithUrls:(nonnull NSMutableSet<NSURL *> *)urls;
- (void) addUrl:(nonnull NSURL *)url;
@end


@interface NiFiSiteToSiteClientConfig : NSObject <NSCopying>

@property (nonatomic, retain, readwrite, nonnull) NSMutableArray<NiFiSiteToSiteRemoteClusterConfig *> *remoteClusters;
@property (nonatomic, retain, readwrite, nonnull) NSString *portName;  // Name of S2S input port at the server's configured flow
                                                                       // to which to send flow files.
                                                                       // Optional, not needed if portId is set.
@property (nonatomic, retain, readwrite, nonnull) NSString *portId;    // ID of S2S input port at the server's configured flow
                                                                       // to which to send flow files.
                                                                       // Optional, not needed if portName is set.
@property (nonatomic, readwrite) NSTimeInterval peerUpdateInterval;    // Update interval for refreshing peer list if remote is a multi-instance NiFi cluster. Set to 0 to disable. Defaults to 0 (disabled)
+ (nullable instancetype) configWithRemoteCluster:(nonnull NiFiSiteToSiteRemoteClusterConfig *)remoteClusterConfig;
+ (nullable instancetype) configWithRemoteClusters:(nonnull NSArray<NiFiSiteToSiteRemoteClusterConfig *> *)remoteClusterConfigs;

- (void) addRemoteCluster:(nonnull NiFiSiteToSiteRemoteClusterConfig *)clusterConfig;
@end



// MARK: - SiteToSite Client, DataPacket, Transaction -

@interface NiFiDataPacket : NSObject

+ (nonnull instancetype)dataPacketWithAttributes:(nonnull NSDictionary<NSString *, NSString *> *)attributes
                                            data:(nullable NSData *)data;
+ (nonnull instancetype)dataPacketWithAttributes:(nonnull NSDictionary<NSString *, NSString *> *)attributes
                                      dataStream:(nullable NSInputStream *)dataStream
                                      dataLength:(NSUInteger)length;
+ (nonnull instancetype)dataPacketWithString:(nonnull NSString *)string;
+ (nullable instancetype)dataPacketWithFileAtPath:(nonnull NSString *)filePath;

- (void)setAttributeValue:(nullable NSString *)value forAttributeKey:(nonnull NSString *)key;

- (nonnull NSDictionary<NSString *, NSString *> *)attributes;
- (nullable NSData *)data;
- (nullable NSInputStream *)dataStream;
- (NSUInteger)dataLength;

@end


@interface NiFiPeer : NSObject

@property (nonatomic, retain, readwrite, nonnull) NSURL *url;
// @property (nonatomic, readwrite) NSUInteger rawPort;
// @property (nonatomic, readwrite) BOOL secure;
@property (nonatomic, readwrite) NSUInteger flowFileCount;
@property (nonatomic, readwrite) NSTimeInterval lastFailure; // TimeIntervalSinceReferenceDate, should be updated using markFailure

+ (nullable instancetype)peerWithUrl:(nonnull NSURL *)url;
//+ (nullable instancetype)peerWithUrl:(nonnull NSURL *)url rawPort:(NSUInteger)rawPort secure:(BOOL)isSecure;

- (void)markFailure;

// returns an object that implements hash/isEqual for the Peer instance, so can be used in NSDictionary, HashSet, etc.
- (nonnull id)peerKey;

// for use in sorting situations.
- (NSComparisonResult)compare:(nonnull NiFiPeer *)other;

@end



@interface NiFiTransactionResult : NSObject
@property (nonatomic, readonly) uint64_t dataPacketsTransferred;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly, nullable) NSString *message;
- (bool)shouldBackoff;
@end


@protocol NiFiTransaction <NSObject>
- (nonnull NSString *)transactionId;
- (NiFiTransactionState)transactionState;
- (void)sendData:(nonnull NiFiDataPacket *)data;
- (void)cancel; // cancel the transaction
- (void)error;  // mark the transaction as having encountered an error
- (nullable NiFiTransactionResult *)confirmAndCompleteOrError:(NSError *_Nullable *_Nullable)error;
- (nullable NiFiPeer *)getCommunicant;
@end


@interface NiFiSiteToSiteClient : NSObject
+ (nonnull instancetype)clientWithConfig:(nonnull NiFiSiteToSiteClientConfig *)config;
- (nullable NSObject <NiFiTransaction> *)createTransaction;
- (nullable NSObject <NiFiTransaction> *)createTransactionWithURLSession:(NSURLSession *_Nonnull)urlSession;
@end



// MARK: - SiteToSite Util -

@interface NiFiSiteToSiteUtil : NSObject
+ (nonnull NSString *)NiFiTransactionStateToString:(NiFiTransactionState)state;
@end


#endif /* NiFiSiteToSite_h */
