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
#import "NiFiSiteToSiteServicePrivate.h"
#import "NiFiSiteToSiteClientPrivate.h"
#import "NiFiSiteToSiteDatabase.h"
#import "NiFiError.h"

// static const int SECONDS_TO_NANOS = 1000000000;

/********** No Op DataPacketPrioritizer Implementation **********/

@interface NiFiNoOpDataPacketPrioritizer()
@property (nonatomic) NSInteger fixedTtlMillis;
@end

@implementation NiFiNoOpDataPacketPrioritizer

+(nonnull instancetype)prioritizer {
    return [self prioritizerWithFixedTTL:1.0];
}

+(nonnull instancetype)prioritizerWithFixedTTL:(NSTimeInterval)ttl {
    return [[self alloc] initWithFixedTTL:ttl];
}

- initWithFixedTTL:(NSTimeInterval)ttl {
    self = [super init];
    if (self) {
        _fixedTtlMillis = (NSInteger)(ttl * 1000.0); // convert NSTimeInterval to millis
    }
    return self;
}

- (NSInteger)priorityForDataPacket:(nonnull NiFiDataPacket *)dataPacket {
    return 0;
}

- (NSInteger)ttlMillisForDataPacket:(nonnull NiFiDataPacket *)dataPacket {
    return _fixedTtlMillis;
}

@end

/********** QueuedSiteToSiteConfig Implementation **********/

static const int QUEUED_S2S_CONFIG_DEFAULT_MAX_PACKET_COUNT = 10000L;
static const int QUEUED_S2S_CONFIG_DEFAULT_MAX_PACKET_SIZE = 100L * 1024L * 1024L; // 100 MB
static const int QUEUED_S2S_CONFIG_DEFAULT_BATCH_COUNT = 100L;
static const int QUEUED_S2S_CONFIG_DEFAULT_BATCH_SIZE = 1024L * 1024L; // 1 MB

@implementation NiFiQueuedSiteToSiteClientConfig

-(instancetype)init {
    self = [super init];
    if (self) {
        _maxQueuedPacketCount = [NSNumber numberWithInteger:QUEUED_S2S_CONFIG_DEFAULT_MAX_PACKET_COUNT];
        _maxQueuedPacketSize = [NSNumber numberWithInteger:QUEUED_S2S_CONFIG_DEFAULT_MAX_PACKET_SIZE];
        _preferredBatchCount = [NSNumber numberWithInteger:QUEUED_S2S_CONFIG_DEFAULT_BATCH_COUNT];
        _preferredBatchSize = [NSNumber numberWithInteger:QUEUED_S2S_CONFIG_DEFAULT_BATCH_SIZE];
        _dataPacketPrioritizer = [[NiFiNoOpDataPacketPrioritizer alloc] init];
    }
    return self;
}

@end

/********** QueuedSiteToSiteClient Implementation **********/

@interface NiFiQueuedSiteToSiteClient()

@property NiFiQueuedSiteToSiteClientConfig *config;
@property NiFiSiteToSiteDatabase *database;

@end


@implementation NiFiQueuedSiteToSiteClient

+ (nonnull instancetype)clientWithConfig:(nonnull NiFiQueuedSiteToSiteClientConfig *)config {
    return [[self alloc] initWithConfig:config];
}

- (instancetype)initWithConfig:(nonnull NiFiQueuedSiteToSiteClientConfig *)config {
    return [self initWithConfig:config
                       database:[NiFiSiteToSiteDatabase sharedDatabase]];
}

- (nullable instancetype)initWithConfig:(nonnull NiFiQueuedSiteToSiteClientConfig *)config
                               database:(nonnull NiFiSiteToSiteDatabase *)database
{
    self = [super init];
    if (self != nil) {
        _config = config;
        _database = database;
    }
    return self;
}

- (void) enqueueDataPacket:(nonnull NiFiDataPacket *)dataPacket error:(NSError *_Nullable *_Nullable)error {
    [self enqueueDataPackets:[NSArray arrayWithObjects:dataPacket, nil] error:error];
}

- (void) enqueueDataPackets:(nonnull NSArray *)dataPackets error:(NSError *_Nullable *_Nullable)error {
    
    if ([dataPackets count] <= 0) {
        return;
    }
    
    NSMutableArray *entitiesToInsert = [[NSMutableArray alloc] initWithCapacity:[dataPackets count]];
    for (NiFiDataPacket *packet in dataPackets) {
        NiFiQueuedDataPacketEntity *queuedPacketEntity = [NiFiQueuedDataPacketEntity entityWithDataPacket:packet
                                                                                        packetPrioritizer:_config.dataPacketPrioritizer];
        [entitiesToInsert addObject:queuedPacketEntity];
    }
    [_database insertQueuedDataPackets:entitiesToInsert error:error];
    
}

- (void) processOrError:(NSError *_Nullable *_Nullable)error {
    
    NiFiSiteToSiteClient *client = [NiFiSiteToSiteClient clientWithConfig:_config];
    id transaction = [client createTransaction];
    NSString *transactionId = [transaction transactionId];
    if (!transaction && transactionId) {
        if (error) {
            *error = [NSError errorWithDomain:NiFiErrorDomain
                                           code:NiFiErrorSiteToSiteClientCouldNotCreateTransaction
                                       userInfo:nil];
        }
        return;
    }
    
    NSError *dbError;
    [_database createBatchWithTransactionId:transactionId
                                 countLimit:[_config.preferredBatchCount unsignedIntegerValue]
                              byteSizeLimit:[_config.preferredBatchSize unsignedIntegerValue]
                                      error:&dbError];
    
    if (dbError) {
        NSLog(@"Encountered error with domain='%@' code='%ld", [*error domain], (long)[*error code]);
        if (error) {
            *error = dbError;
        }
        return;
    }
    
    NSError *transactionError;
    NSArray<NiFiQueuedDataPacketEntity *> *entitiesToSend = [_database getPacketsWithTransactionId:transactionId];
    for (NiFiQueuedDataPacketEntity *entity in entitiesToSend) {
        [transaction sendData:[entity dataPacket]];
        [transaction confirmAndCompleteOrError:&transactionError];
    }
    
    if (transactionError) {
        NSLog(@"Encountered error with domain='%@' code='%ld", [*error domain], (long)[*error code]);
        if (error) {
            *error = transactionError;
        }
        [_database markPacketsForRetryWithTransactionId:transactionId];
        return;
    } else {
        // successfully sent data packets; clear them from the queue
        [_database deletePacketsWithTransactionId:transactionId];
    }
}

- (void) cleanupOrError:(NSError *_Nullable *_Nullable)error {
    
    // delete expired packets
    [_database ageOffExpiredQueuedDataPacketsOrError:error];
    
    // delete lowest priority packets over row count limit
    NSInteger maxCount = _config.maxQueuedPacketCount ? [_config.maxQueuedPacketCount integerValue] : 0;
    [_database truncateQueuedDataPacketsMaxRows:maxCount error:error];
    
    // delete lowest priority packets over the packet byte size limit
    NSInteger maxBytes = _config.maxQueuedPacketSize ? [_config.maxQueuedPacketSize integerValue] : 0;
    [_database truncateQueuedDataPacketsMaxBytes:maxBytes error:error];
}

@end


/********** SiteToSiteService Implementation **********/

@implementation NiFiSiteToSiteService

// TODO, create background-able NSURLSession, as described in "Downloading Content in the Background" here:
// https://developer.apple.com/library/content/documentation/iPhone/Conceptual/iPhoneOSProgrammingGuide/BackgroundExecution/BackgroundExecution.html

+ (void)sendDataPacket:(nonnull NiFiDataPacket *)packet
siteToSiteClientConfig:(nonnull NiFiSiteToSiteClientConfig *)config
     completionHandler:(void (^_Nullable)(NiFiTransactionResult *_Nullable result, NSError *_Nullable error))completionHandler {
    NSArray *packets = [NSArray arrayWithObjects:packet, nil];
    [[self class] sendDataPackets:packets
           siteToSiteClientConfig:config
                completionHandler:completionHandler];
}

+ (void)sendDataPackets:(nonnull NSArray *)packets
 siteToSiteClientConfig:(nonnull NiFiSiteToSiteClientConfig *)config
      completionHandler:(void (^_Nullable)(NiFiTransactionResult *_Nullable result, NSError *_Nullable error))completionHandler {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NiFiTransactionResult *result = nil;
        NSError *error = nil;
        
        NiFiSiteToSiteClient *s2sClient = [NiFiSiteToSiteClient clientWithConfig:config];
        id transaction = [s2sClient createTransaction];
        if (transaction) {
            for (NiFiDataPacket *packet in packets) {
                [transaction sendData:packet];
            }
            result = [transaction confirmAndCompleteOrError:&error];
        } else {
            error = [NSError errorWithDomain:NiFiErrorDomain
                                        code:NiFiErrorSiteToSiteClientCouldNotCreateTransaction
                                    userInfo:@{NSLocalizedDescriptionKey: @"Could not create site-to-site transaction. Check configuration and remote cluster reachability."}];
        }
        
        completionHandler(result, error);
    });
}

+ (void)enqueueDataPacket:(nonnull NiFiDataPacket *)packet
   siteToSiteClientConfig:(nonnull NiFiQueuedSiteToSiteClientConfig *)config
        completionHandler:(void (^_Nullable)(NSError *_Nullable error))completionHandler {
    
    NSArray *packets = [NSArray arrayWithObjects:packet, nil];
    
    return [[self class] enqueueDataPackets:packets
                     siteToSiteClientConfig:config
                          completionHandler:completionHandler];
}

+ (void)enqueueDataPackets:(nonnull NSArray *)packets
    siteToSiteClientConfig:(nonnull NiFiQueuedSiteToSiteClientConfig *)config
         completionHandler:(void (^_Nullable)(NSError *_Nullable error))completionHandler {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSError *error = nil;
        NiFiQueuedSiteToSiteClient *s2sClient = [NiFiQueuedSiteToSiteClient clientWithConfig:config];
        [s2sClient enqueueDataPackets:packets error:&error];
        completionHandler(error);
    });
}

+ (void)processQueuedPackets:(nonnull NSArray *)packets
      siteToSiteClientConfig:(nonnull NiFiQueuedSiteToSiteClientConfig *)config
           completionHandler:(void (^_Nullable)(NSError *_Nullable error))completionHandler {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NiFiQueuedSiteToSiteClient *s2sClient = [NiFiQueuedSiteToSiteClient clientWithConfig:config];
        [s2sClient processOrError:&error];
        completionHandler(error);
    });
}

+ (void)cleanupQueuedPackets:(nonnull NSArray *)packets
      siteToSiteClientConfig:(nonnull NiFiQueuedSiteToSiteClientConfig *)config
           completionHandler:(void (^_Nullable)(NSError *_Nullable error))completionHandler {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSError *error = nil;
        NiFiQueuedSiteToSiteClient *s2sClient = [NiFiQueuedSiteToSiteClient clientWithConfig:config];
        [s2sClient cleanupOrError:&error];
        completionHandler(error);
    });
}

@end


