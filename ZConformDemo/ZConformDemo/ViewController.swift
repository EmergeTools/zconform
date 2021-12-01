//
//  ViewController.swift
//  ZConformDemo
//
//  Created by Noah Martin on 11/30/21.
//

import UIKit
import ZConform

protocol TestProtocol { }

protocol TestProtocol2 { }

struct TestStructConforms: TestProtocol2 { }

struct TestStruct2Conforms: TestProtocol2 { }

struct TestStructNoConformance { }

struct TestStruct2NoConformance { }

class ViewController: UIViewController {
  
  func makeTestClass0() -> Any {
    return TestClass0()
  }
  
  func makeTestStructNoConformance() -> Any {
    return TestStructNoConformance()
  }
  
  func makeTestStruct2NoConformance() -> Any {
    return TestStruct2NoConformance()
  }
  
  func makeTestStructConforms() -> Any {
    return TestStructConforms()
  }
  
  func makeTestStruct2Conforms() -> Any {
    return TestStruct2Conforms()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    var startTime = CACurrentMediaTime()
    let _ = makeTestClass0() as? TestProtocol
    print("First conformance check duration \((CACurrentMediaTime() - startTime) * 1000)ms")
    
    startTime = CACurrentMediaTime()
    ZConformHelper.setup()
    print("ZConform setup duration \((CACurrentMediaTime() - startTime) * 1000)ms")
    
    startTime = CACurrentMediaTime()
    let _ = makeTestStructNoConformance() as? TestProtocol
    print("Time for swift runtime failed conformance check \((CACurrentMediaTime() - startTime) * 1000)ms")
    
    startTime = CACurrentMediaTime()
    let result = zconform(makeTestStructNoConformance(), TestProtocol.self)
    print("Time for zconform failed conformance check \((CACurrentMediaTime() - startTime) * 1000)ms")
    print(result == nil)
    
    startTime = CACurrentMediaTime()
    let _ = makeTestStructConforms() as? TestProtocol2
    print("Time for swift runtime conformance check \((CACurrentMediaTime() - startTime) * 1000)ms")
    
    startTime = CACurrentMediaTime()
    let result2 = zconform(makeTestStruct2Conforms(), TestProtocol2.self)
    print("Time for zconform conformance check \((CACurrentMediaTime() - startTime) * 1000)ms")
    print(result2 != nil)
  }

}
