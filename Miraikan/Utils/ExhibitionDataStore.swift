//
//  ExhibitionDataStore.swift
//  NavCogMiraikan
//
/*******************************************************************************
 * Copyright (c) 2021 © Miraikan - The National Museum of Emerging Science and Innovation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *******************************************************************************/

import Foundation

struct ExhibitionLocation : Decodable {
    let nodeId: String
    let floor: Int
}

struct ExhibitionModel : Decodable {
    let id : String
    let nodeId : String?
    let title : String
    let category : String
    let counter : String
    let floor : Int?
    let locations : [ExhibitionLocation]?
    let description : String
    let blindModeIntro : String
}

struct ScheduleModel : Decodable {
    let time: String
    let place: String
    let event: String
    let description: String?
    let onHoliday: Bool?
}

struct EventModel : Decodable {
    let id: String
    let title: String
    let talkTitle: String?
    let imageType: String
    let schedule: [String]?
    let description: [String]?
    let content: String
}

// Singleton for exhibition data transfer
class ExhibitionDataStore {
    
    static let shared = ExhibitionDataStore()
    
    var exhibitions: [ExhibitionModel]?
    
    var schedules: [ScheduleModel]?
    
    var events: [EventModel]?
    
}