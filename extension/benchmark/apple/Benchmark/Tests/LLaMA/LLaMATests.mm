/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ResourceTestCase.h"

#import <executorch/examples/models/llama/runner/runner.h>

using namespace ::executorch::extension;
using namespace ::executorch::runtime;

@interface TokensPerSecondMetric : NSObject<XCTMetric>

@property(nonatomic, assign) NSUInteger tokenCount;

@end

@implementation TokensPerSecondMetric

- (id)copyWithZone:(NSZone *)zone {
  TokensPerSecondMetric *copy = [[[self class] allocWithZone:zone] init];
  copy.tokenCount = self.tokenCount;
  return copy;
}

- (NSArray<XCTPerformanceMeasurement *> *)
    reportMeasurementsFromStartTime:
        (XCTPerformanceMeasurementTimestamp *)startTime
                          toEndTime:
                              (XCTPerformanceMeasurementTimestamp *)endTime
                              error:(NSError **)error {
  double elapsedTime =
      (endTime.absoluteTimeNanoSeconds - startTime.absoluteTimeNanoSeconds) /
      (double)NSEC_PER_SEC;
  return @[ [[XCTPerformanceMeasurement alloc]
      initWithIdentifier:NSStringFromClass([self class])
             displayName:@"Tokens Per Second"
             doubleValue:(self.tokenCount / elapsedTime)
              unitSymbol:@"t/s"] ];
}

@end

@interface LLaMATests : ResourceTestCase
@end

@implementation LLaMATests

+ (NSArray<NSString *> *)directories {
  return @[
    @"Resources",
    @"aatp/data", // AWS Farm devices look for resources here.
  ];
}

+ (NSDictionary<NSString *, BOOL (^)(NSString *)> *)predicates {
  return @{
    @"model" : ^BOOL(NSString *filename){
      return [filename hasSuffix:@".pte"] && [filename.lowercaseString containsString:@"llm"];
    },
    @"tokenizer" : ^BOOL(NSString *filename) {
      return [filename isEqual:@"tokenizer.bin"] || [filename isEqual:@"tokenizer.model"] || [filename isEqual:@"tokenizer.json"];
    },
  };
}

+ (NSDictionary<NSString *, void (^)(XCTestCase *)> *)dynamicTestsForResources:
    (NSDictionary<NSString *, NSString *> *)resources {
  NSString *modelPath = resources[@"model"];
  NSString *tokenizerPath = resources[@"tokenizer"];
  return @{
    @"generate" : ^(XCTestCase *testCase){
      auto __block runner = example::create_llama_runner(
          modelPath.UTF8String, tokenizerPath.UTF8String);
      if (!runner) {
        XCTFail("Failed to create runner");
        return;
      }
      const auto status = runner->load();
      if (status != Error::Ok) {
        XCTFail("Load failed with error %i", status);
        return;
      }
      TokensPerSecondMetric *tokensPerSecondMetric = [TokensPerSecondMetric new];
      [testCase measureWithMetrics:@[ tokensPerSecondMetric, [XCTClockMetric new], [XCTMemoryMetric new] ]
                            block:^{
                              tokensPerSecondMetric.tokenCount = 0;
                              // Create a GenerationConfig object
                              ::executorch::extension::llm::GenerationConfig config{
                                .max_new_tokens = 50,
                                .warming = false,
                              };

                              const auto status = runner->generate(
                                  "Once upon a time",
                                  config,
                                  [=](const std::string &token) {
                                    tokensPerSecondMetric.tokenCount++;
                                  });
                              XCTAssertEqual(status, Error::Ok);
                            }];
    },
  };
}

@end
