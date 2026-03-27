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
  var isFavorite: Bool

  init(
    id: UUID = UUID(), description: String, mode: SearchMode, isParatransitMode: Bool,
    isFavorite: Bool = false
  ) {
    self.id = id
    self.description = description
    self.mode = mode
    self.isParatransitMode = isParatransitMode
    self.isFavorite = isFavorite
  }
}
