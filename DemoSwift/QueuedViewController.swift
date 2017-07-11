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

import UIKit

import s2s

class QueuedViewController: UIViewController {
    
    let SECONDS_TO_NANOS = 1000000000
    let queueProcessingInterval = TimeInterval(5.0)
    var s2sClientConfig: NiFiQueuedSiteToSiteClientConfig!
    
    var buttonClicksSinceLoad = 0;
    var amount = 10;
    @IBOutlet var amountLabel: UILabel!
    @IBOutlet var amountSlider: UISlider!
    @IBOutlet var queueCountLabel: UILabel!
    @IBOutlet var queueCountCapacityBar: UIProgressView!
    @IBOutlet var queueProcessingSwitch: UISwitch!
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        s2sClientConfig = NiFiQueuedSiteToSiteClientConfig()
        s2sClientConfig.host = UserDefaults.standard.string(forKey: "nifi.s2s.config.host")!
        s2sClientConfig.port = NSNumber(value: UserDefaults.standard.integer(forKey: "nifi.s2s.config.port"))
        s2sClientConfig.portId = UserDefaults.standard.string(forKey: "nifi.s2s.config.portId")!
        s2sClientConfig.secure = UserDefaults.standard.bool(forKey: "nifi.s2s.config.secure")
        if s2sClientConfig.secure {
            s2sClientConfig.username = UserDefaults.standard.string(forKey: "nifi.s2s.config.secure.username")
            s2sClientConfig.password = UserDefaults.standard.string(forKey: "nifi.s2s.config.secure.password")
        }
        s2sClientConfig.maxQueuedPacketCount = NSNumber(
            value: UserDefaults.standard.integer(forKey: "nifi.s2s.config.queued.max_queued_packet_count"))
        s2sClientConfig.maxQueuedPacketSize = NSNumber(
            value: UserDefaults.standard.integer(forKey: "nifi.s2s.config.queued.max_queued_packet_size"))
        s2sClientConfig.preferredBatchCount = NSNumber(
            value: UserDefaults.standard.integer(forKey: "nifi.s2s.config.queued.preferred_batch_count"))
        s2sClientConfig.preferredBatchSize = NSNumber(
            value: UserDefaults.standard.integer(forKey: "nifi.s2s.config.queued.preferred_batch_size"))
        
        s2sClientConfig.dataPacketPrioritizer = NiFiNoOpDataPacketPrioritizer(fixedTTL: 60.0)
        s2sClientConfig.urlSessionConfiguration = AppNetworkingUtils.demoUrlSessionConfiguration()
        s2sClientConfig.urlSessionDelegate = AppURLSessionDelegate()
        
        // Other setup
        updateCreationAmount()
        
        // Register for UI events
        queueProcessingSwitch.addTarget(self, action: #selector(queueProcessingSwitchChanged), for: UIControlEvents.valueChanged)
    }
    
    func updateCreationAmount() {
        amount = Int(amountSlider.value * s2sClientConfig.maxQueuedPacketCount.floatValue)
        if (amount <= 0) {
            amount = 1;
        }
        amountLabel.text = String(amount);
    }
    
    @IBAction func amountSliderValueChanged(_ sender: Any) {
        updateCreationAmount()
    }
    
    @IBAction func enqueueButtonClicked(_ sender: Any) {
        buttonClicksSinceLoad += 1
        
        updateCreationAmount()
        let dataPackets = NSMutableArray(capacity: amount)
        for i in 0...amount-1 {
            dataPackets[i] = NiFiDataPacket(attributes: ["clickEvent": String(buttonClicksSinceLoad),
                                                         "packetNumber": String(i)],
                                            data: "This is the content of the data packet".data(using: String.Encoding.utf8))
        }
        NiFiSiteToSiteService.enqueueDataPackets(dataPackets as! [Any], config: s2sClientConfig, completionHandler: queuedOperationCompleted)
    }
    
    func queueProcessingSwitchChanged() {
        if(queueProcessingSwitch.isOn) {
            scheduleNextQueueProcessingEvent(withDelay: 0.0)
        }
    }
    
    func scheduleNextQueueProcessingEvent(withDelay: TimeInterval) {
        if(queueProcessingSwitch.isOn) {
            NSLog("Scheduling background task to send batch of queued packets to NiFi.")
            let nextProcessTime = DispatchTime.now() + withDelay
            DispatchQueue.global().asyncAfter(deadline: nextProcessTime) {
                if (self.queueProcessingSwitch.isOn) {
                    NiFiSiteToSiteService.processQueuedPackets(with: self.s2sClientConfig,
                                                               completionHandler: self.queuedOperationCompleted)
                    self.scheduleNextQueueProcessingEvent(withDelay: self.queueProcessingInterval)
                }
            }
        }
    }
    
    func queuedOperationCompleted(status: NiFiSiteToSiteQueueStatus?, error: Error?) {
        if (status != nil) {
            DispatchQueue.main.async {
                // Update Queue Count Label
                self.queueCountLabel.text = String(status!.queuedPacketCount)
                
                // Update Queue Count Capacity Bar
                let queueCountCapacityFraction = (Float(status!.queuedPacketCount) / Float(self.s2sClientConfig.maxQueuedPacketCount))
                self.queueCountCapacityBar.setProgress(queueCountCapacityFraction, animated: true)
                self.view.setNeedsDisplay()
            }
        }
    }
}



