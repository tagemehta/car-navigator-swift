//  SearchHistoryItem.swift
//  thing-finder
//
//  Model for storing search history with mode and paratransit settings

import Foundation

struct SearchHistoryItem: Codable, Identifiable {
  let id: UUID
  let description: String
  let mode: SearchMode
  let isParatransitMode: Bool
  
  init(description: String, mode: SearchMode, isParatransitMode: Bool) {
    self.id = UUID()
    self.description = description
    self.mode = mode
    self.isParatransitMode = isParatransitMode
  }
}
