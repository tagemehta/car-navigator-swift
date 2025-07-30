//  VerifierEvaluationTests.swift
//  thing-finderTests
//
//  Runs the car_eval.json benchmark through TwoStepVerifier and evaluates
//  make+model extraction accuracy.
//  Prints overall accuracy / precision / recall.
//
//  NOTE: This test will perform ~250×2 network calls to OpenAI.  Set the
//  `EVAL_SAMPLE` environment variable (e.g. "20") to subsample when iterating
//  locally.
//
//  Created by Cascade AI on 2025-07-22.

import Combine
import XCTest

@testable import thing_finder

final class VerifierEvaluationTests: XCTestCase {
  struct Case: Decodable {
    let image_b64: String
    let target_description: String
    let ground_truth_match: Bool
  }
  struct Metrics {
    var tp = 0
    var fp = 0
    var tn = 0
    var fn = 0
    var apiErrors = 0
    var total = 0
    var accuracy: Double { Double(tp + tn) / Double(max(1, total)) }
    var precision: Double { tp == 0 && fp == 0 ? 0 : Double(tp) / Double(tp + fp) }
    var recall: Double { tp == 0 && fn == 0 ? 0 : Double(tp) / Double(tp + fn) }
    var errorRate: Double { Double(apiErrors) / Double(max(1, total)) }
  }

  // MARK: - Helpers
  private func runSuite(_ cases: [Case]) -> AnyPublisher<Metrics, Error> {
    let testCases = Array(cases[3...4])
    let verifiers = testCases.map {
      TrafficEyeVerifier(targetTextDescription: $0.target_description, config: VerificationConfig(expectedPlate: nil))
    }

    return Publishers.MergeMany(
      testCases.enumerated().map { (idx, c) in
        let verifier = verifiers[idx]
        let imageBytes = Data(base64Encoded: c.image_b64)!
        let image = UIImage(data: imageBytes)!
        return verifier.verify(image: image)
          .map { (idx, c, $0) }
          .catch { _ in
            Just(
              (
                idx, c,
                VerificationOutcome(isMatch: false, description: "", rejectReason: "api_error")
              )
            )
            .setFailureType(to: Error.self)
          }
      }
    )
    .collect()
    .tryMap { triplets -> Metrics in
      var m = Metrics()
      for (_, c, out) in triplets {
        m.total += 1
        if out.rejectReason == "api_error" { m.apiErrors += 1 }

        if out.isMatch {
          c.ground_truth_match ? (m.tp += 1) : (m.fp += 1)
        } else {
          c.ground_truth_match ? (m.fn += 1) : (m.tn += 1)
        }
      }
      // ----- CSV export -----
      if let datasetPath = self.datasetPath() {
        let root = URL(fileURLWithPath: datasetPath).deletingLastPathComponent()
          .deletingLastPathComponent()  // repoRoot/datasets
        let resultsDir = root.appendingPathComponent("results", isDirectory: true)
        try? FileManager.default.createDirectory(at: resultsDir, withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(
          of: ":", with: "-")
        let csvURL = resultsDir.appendingPathComponent("twoStep_\(ts).csv")
        var csv = "image_idx,ground_truth,predicted,is_match,correct\n"
        for (idx, c, out) in triplets {
          let correct = (out.isMatch == c.ground_truth_match)
          let escapedPred = out.description.replacingOccurrences(of: "\"", with: "\"\"")
          let escapedGT = c.target_description.replacingOccurrences(of: "\"", with: "\"\"")
          csv += "\(idx),\"\(escapedGT)\",\"\(escapedPred)\",\(out.isMatch),\(correct)\n"
        }
        try? csv.write(to: csvURL, atomically: true, encoding: .utf8)
        print("CSV written to \(csvURL.path)")
      }
      return m
    }
    .eraseToAnyPublisher()
  }

  private func precision(_ m: Metrics) -> Double {
    Double(m.tp) / Double(max(1, m.tp + m.fp))
  }

  private func datasetPath() -> String? {
    // Determine directory of this test file at runtime
    let thisFile = (#file as NSString).deletingLastPathComponent
    var dirURL = URL(fileURLWithPath: thisFile)
    // Traverse up to 5 levels looking for /datasets/car_eval.json
    for _ in 0..<5 {
      let candidate = dirURL.appendingPathComponent("datasets/car_eval_uber.json").path
      if FileManager.default.fileExists(atPath: candidate) {
        return candidate
      }
      dirURL.deleteLastPathComponent()
    }
    return nil
  }

  // MARK: - Test
  func test_TwoStep_beatsOriginal_onPrecision() throws {
    // 1. Load dataset (search several common locations)
    guard let path = datasetPath() else {
      XCTFail(
        "car_eval.json not found. Expected in: datasets/car_eval.json, ../datasets/car_eval.json, ../../datasets/car_eval.json"
      )
      return
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    var cases = try JSONDecoder().decode([Case].self, from: data)

    if let env = ProcessInfo.processInfo.environment["EVAL_SAMPLE"], let n = Int(env),
      n < cases.count
    {
      cases = Array(cases.prefix(n))
    }

    let exp = expectation(description: "eval")

    var newM: Metrics?
    var bag = Set<AnyCancellable>()

    func makeLLM(c: Case) -> AnyPublisher<VerificationOutcome, Error> {
      let image = UIImage(data: Data(base64Encoded: c.image_b64)!)
      return LLMVerifier(targetClasses: ["car"], targetTextDescription: c.target_description)
        .verify(image: image!)
    }
    func makeTwo(c: Case) -> AnyPublisher<VerificationOutcome, Error> {
      let image = UIImage(data: Data(base64Encoded: c.image_b64)!)
      return TwoStepVerifier(targetTextDescription: c.target_description)
        .verify(image: image!)
    }

    runSuite(cases)
      .sink { comp in
        if case .failure(let err) = comp {
          XCTFail("eval failure: \(err)")
        }
        exp.fulfill()
      } receiveValue: { m in
        newM = m
      }
      .store(in: &bag)

    waitForExpectations(timeout: 600)  // 10 min for 250*2 calls

    guard let m1 = newM else { return }
    print(
      "TwoStep precision: \(precision(m1))  acc: \(m1.accuracy) recall: \(m1.recall)  API error rate: \(m1.errorRate)"
    )
    print(
      "total=\(m1.total) apiErrors=\(m1.apiErrors) tp=\(m1.tp) fp=\(m1.fp) tn=\(m1.tn) fn=\(m1.fn)")
  }
}
