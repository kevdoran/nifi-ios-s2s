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

#ifndef NiFiHttpSiteToSiteClient_h
#define NiFiHttpSiteToSiteClient_h

#import <Foundation/Foundation.h>
#import "NiFiSiteToSiteClientPrivate.h"
#import "NiFiHttpRestApiClient.h"

@interface NiFiHttpSiteToSiteClient : NiFiSiteToSiteClient
@end

// This class is only to be used internally and in test cases.
// Real use should create transactions using a NiFiSiteToSiteClient's createTransaction method.
@interface NiFiHttpTransaction : NSObject <NiFiTransaction>
- (nonnull instancetype) initWithPortId:(nonnull NSString *)portId
                      httpRestApiClient:(nonnull NiFiHttpRestApiClient *)restApiClient;
@property (nonatomic, retain, readwrite, nonnull) NSDate *startTime;
@property (nonatomic, readwrite) NiFiTransactionState transactionState;
@property (atomic, readwrite) bool shouldKeepAlive;
@property (nonatomic, retain, readwrite, nonnull) NiFiHttpRestApiClient *restApiClient;
@property (nonatomic, readwrite, nonnull) NiFiTransactionResource *transactionResource;
@property (nonatomic, readwrite, nonnull) NSOutputStream *dataPacketWriterOutputStream;
@property (nonatomic, readwrite, nonnull) NiFiDataPacketEncoder *dataPacketEncoder;
@end

#endif /* HttpSiteToSiteClient_h */
