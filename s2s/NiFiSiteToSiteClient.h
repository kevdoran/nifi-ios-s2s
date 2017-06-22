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

/* 
 * NiFiSiteToSiteClient.h
 * Public Header, Site To Site Client Interface
 */

#ifndef NiFiSiteToSiteClient_h
#define NiFiSiteToSiteClient_h

#import <Foundation/Foundation.h>


typedef enum {
    HTTP,
    // RAW_SOCKET, // TODO, if needed, there is also a the socket variant of the NiFi Site-to-Site protocol that could be implemented
} NiFiSiteToSiteTransportProtocol;

typedef enum {
    TRANSACTION_STARTED,
    DATA_EXCHANGED,
    TRANSACTION_CONFIRMED,
    TRANSACTION_COMPLETED,
    TRANSACTION_CANCELED,
    TRANSACTION_ERROR
} NiFiTransactionState;


@interface NiFiDataPacket : NSObject

+ (nonnull instancetype)dataPacketWithAttributes:(nonnull NSDictionary<NSString *, NSString *> *)attributes
                                            data:(nullable NSData *)data;
+ (nonnull instancetype)dataPacketWithAttributes:(nonnull NSDictionary<NSString *, NSString *> *)attributes
                                      dataStream:(nullable NSInputStream *)dataStream
                                      dataLength:(NSUInteger)length;
+ (nonnull instancetype)dataPacketWithString:(nonnull NSString *)string;
//+ (nonnull instancetype)dataPacketWithFileAtPath:(nonnull NSString *)filePath;

- (nonnull NSDictionary<NSString *, NSString *> *)attributes;
- (nullable NSData *)data;
- (nullable NSInputStream *)dataStream;
- (NSUInteger)dataLength;

@end

// TODO add NiFiMutableDataPacket to public API ?
//@interface NiFiMutableDataPacket : NiFiDataPacket
//@end


@protocol NiFiCommunicant <NSObject>
- (nullable NSURL *)url;
- (nullable NSString *)host;
- (nullable NSNumber *)port;
@end


@interface NiFiTransactionResult : NSObject
@property (nonatomic, readonly) uint64_t dataPacketsTransferred;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly, nullable) NSString *message;
- (bool)shouldBackoff;
@end

@protocol NiFiTransaction <NSObject>
- (NiFiTransactionState)transactionState;
- (void)sendData:(nonnull NiFiDataPacket *)data;
- (nullable NiFiDataPacket *)receive;
- (void)cancel;
- (void)cancelWithExplaination:(nonnull NSString *)explaination;
- (void)error;
- (nonnull NiFiTransactionResult *)confirmAndComplete;
- (nonnull NSObject <NiFiCommunicant> *)getCommunicant;
@end

@interface NiFiSiteToSiteClientConfig : NSObject <NSCopying>
@property (nonatomic, retain, readwrite, nonnull) NSString *host;  // no default, must be set
@property (nonatomic, retain, readwrite, nonnull) NSNumber *port;  // no default, must be set
@property (nonatomic, retain, readwrite, nonnull) NSString *portId;  // no default, must be set
@property (nonatomic, readwrite) NiFiSiteToSiteTransportProtocol transportProtocol;  // defaults to HTTP
@property (nonatomic, readwrite) bool secure;  // defaults to false
@property (nonatomic, assign, readwrite, nullable) NSString *username;  // client credentials for two-way auth; ignored if secure is false
@property (nonatomic, assign, readwrite, nullable) NSString *password;  // client credentials for two-way auth; ignored if secure is false
- (nonnull instancetype)init;
@end

@interface NiFiSiteToSiteClient : NSObject
+ (nonnull instancetype)clientWithConfig:(nonnull NiFiSiteToSiteClientConfig *)config;
- (nonnull NSObject <NiFiTransaction> *)createTransaction;
- (nonnull NSObject <NiFiTransaction> *)createTransactionWithURLSession:(NSURLSession *_Nonnull)urlSession;
- (bool)isSecure;
@end

@interface NiFiUtil : NSObject
+ (nonnull NSString *)NiFiTransactionStateToString:(NiFiTransactionState)state;
@end

#endif /* NiFiSiteToSiteClient_h */
