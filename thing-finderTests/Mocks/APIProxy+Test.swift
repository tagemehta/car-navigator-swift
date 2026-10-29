//  APIProxy+Test.swift
//  thing-finderTests
//
//  Fixed proxy config so MockURLSession can match requests on "proxy.test/<path>".

import Foundation

@testable import thing_finder

extension APIProxy {
  static let test = APIProxy(
    baseURL: URL(string: "https://proxy.test")!,
    appToken: "test-app-token",
    deviceId: "00000000-0000-0000-0000-000000000001"
  )
}
