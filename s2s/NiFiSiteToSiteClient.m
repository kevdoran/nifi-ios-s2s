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
#import "NiFiSiteToSiteClient.h"
#import "NiFiSiteToSiteClientPrivate.h"
#import "NiFiHttpSiteToSiteClient.h"

/********** Communicant/Peer Implementation **********/

@interface NiFiPeer()
@property (nonatomic, retain, readwrite, nonnull) NSURLComponents* urlComponents;
@property (nonatomic, readwrite) NSTimeInterval lastFailure;
@property (nonatomic, readwrite) NSUInteger flowFileCount;
@property (nonatomic, readwrite) bool secure;
@end


@implementation NiFiPeer

- initWithUrl:(nonnull NSURL *)url {
    return [self initWithUrl:url secure:false];
}

- initWithUrl:(nonnull NSURL *)url secure:(bool)isSecure {
    self = [super init];
    if(self != nil) {
        _urlComponents = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:false];
        _secure = isSecure;
        _lastFailure = 0.0;
    }
    return self;
}

- (nullable NSURL *)url {
    return _urlComponents.URL;
}

- (nullable NSString *)host {
    return _urlComponents.host;
}

- (nullable NSNumber *)port {
    return _urlComponents.port;
}

- (void)markFailure {
    _lastFailure = [NSDate timeIntervalSinceReferenceDate];
}

- (NSComparisonResult)compare:(NiFiPeer *)other {
    NSInteger lastFailureMillis = _lastFailure * 1000;
    NSInteger otherlastFailureMillis = other.lastFailure + 1000;
    if (lastFailureMillis > otherlastFailureMillis) {
        return NSOrderedDescending;  // 1
    } else if (lastFailureMillis < otherlastFailureMillis) {
        return NSOrderedAscending;  // -1
    } else if (_flowFileCount > other.flowFileCount) {
        return NSOrderedDescending;
    } else if (_flowFileCount < other.flowFileCount) {
        return NSOrderedAscending;
    } else {
        if (_urlComponents.host) {
            if (other.urlComponents.host) {
                NSInteger hostCompare = [_urlComponents.host compare:other.urlComponents.host];
                if (hostCompare != NSOrderedSame) {
                    return hostCompare;
                }
            } else {
                return NSOrderedAscending;
            }
        }
        if (_urlComponents.port) {
            if (other.urlComponents.port) {
                NSInteger portCompare = [_urlComponents.port compare:other.urlComponents.port];
                if (portCompare != NSOrderedSame) {
                    return portCompare;
                }
            } else {
                return NSOrderedAscending;
            }
        }
    }
    return NSOrderedSame;
}

@end


/********** TransactionCompletion Implementation **********/

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

/********** SiteToSiteClientConfig Implementation **********/

@interface NiFiSiteToSiteClientConfig()
@end

@implementation NiFiSiteToSiteClientConfig

- (instancetype) init {
    self = [super init];
    if(self != nil) {
        _secure = false;
        _transportProtocol = HTTP;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    NiFiSiteToSiteClientConfig * copy = [[NiFiSiteToSiteClientConfig alloc] init];
    copy.host = [_host copyWithZone:zone];
    copy.port = [_port copyWithZone:zone];
    copy.portId = [_portId copyWithZone:zone];
    copy.transportProtocol = _transportProtocol;
    copy.secure = _secure;
    copy.username = [_username copyWithZone:zone];
    copy.password = [_password copyWithZone:zone];
    
    copy.urlSessionConfiguration = [_urlSessionConfiguration copyWithZone:zone];
    copy.urlSessionDelegate = _urlSessionDelegate; // shallow copy
    
    return copy;
}

@end

/********** SiteToSiteClient Implementation **********/

@implementation NiFiSiteToSiteClient

+ (nonnull instancetype) clientWithConfig:(nonnull NiFiSiteToSiteClientConfig *)config {
    NiFiSiteToSiteClientConfig * configCopy = [config copy];
    
    // Create a client subtype based on the transport protocol specified in the config
    switch (config.transportProtocol) {
        case HTTP:
            return [[NiFiHttpSiteToSiteClient alloc] initWithConfig: configCopy];
        default:
            @throw [NSException
                    exceptionWithName:NSGenericException
                    reason:@"Unsupported NiFiSiteToSiteTransportProtocol when creating NiFiSiteToSiteClient."
                    userInfo:nil];
    }
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


/********** NiFiUtil Implementation **********/

@implementation NiFiUtil

+ (nonnull NSString *) NiFiTransactionStateToString:(NiFiTransactionState)state {
    switch(state) {
        case TRANSACTION_STARTED:
            return @"TRANSACTION_STARTED";
        case DATA_EXCHANGED:
            return @"DATA_EXCHANGED";
        case TRANSACTION_CONFIRMED:
            return @"TRANSACTION_CONFIRMED";
        case TRANSACTION_COMPLETED:
            return @"TRANSACTION_COMPLETED";
        case TRANSACTION_CANCELED:
            return @"TRANSACTION_CANCELED";
        case TRANSACTION_ERROR:
            return @"TRANSACTION_ERROR";
        default:
            @throw [NSException
                    exceptionWithName:NSGenericException
                    reason:@"Unexpected NiFiTransactionState."
                    userInfo:nil];
    }
}

@end






