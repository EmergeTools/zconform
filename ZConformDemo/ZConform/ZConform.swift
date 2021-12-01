//
//  ZConform.swift
//  ZConform
//
//  Created by Noah Martin on 11/25/21.
//

import Foundation

struct ProtocolDescriptor {
  let flags: UInt32
  let parent: Int32
  let name: Int32
  let numRequirementsInSignature: UInt32
  let numRequirements: UInt32
  let associatedTypeNames: Int32
}

struct ProtocolMetadataLayout {
    var kind: UInt64
    var flags: UInt32
    var numProtocols: UInt32
}

struct StructMetadataLayout {
  let kind: UInt64
  let descriptorPointer: UInt64
}

enum Kind {
  case `struct`
  case `enum`
  case optional
  case opaque
  case tuple
  case function
  case existential
  case metatype
  case objCClassWrapper
  case existentialMetatype
  case foreignClass
  case heapLocalVariable
  case heapGenericLocalVariable
  case errorObject
  case `class`
  
  init(kind: Int) {
    switch kind {
    case 1, (0 | Flags.kindIsNonHeap):
      self = .struct
    case 2, (1 | Flags.kindIsNonHeap):
      self = .enum
    case 3, (2 | Flags.kindIsNonHeap):
      self = .optional
    case 8, (0 | Flags.kindIsRuntimePrivate | Flags.kindIsNonHeap):
      self = .opaque
    case 16, (3 | Flags.kindIsNonHeap):
      self = .foreignClass
    case 9, (1 | Flags.kindIsRuntimePrivate | Flags.kindIsNonHeap):
      self = .tuple
    case 10, (2 | Flags.kindIsRuntimePrivate | Flags.kindIsNonHeap):
      self = .function
    case 12, (3 | Flags.kindIsRuntimePrivate | Flags.kindIsNonHeap):
      self = .existential
    case 13, (4 | Flags.kindIsRuntimePrivate | Flags.kindIsNonHeap):
      self = .metatype
    case 14, (5 | Flags.kindIsRuntimePrivate | Flags.kindIsNonHeap):
      self = .objCClassWrapper
    case 15, (6 | Flags.kindIsRuntimePrivate | Flags.kindIsNonHeap):
      self = .existentialMetatype
    case 64, (0 | Flags.kindIsNonType):
      self = .heapLocalVariable
    case 65, (0 | Flags.kindIsNonType | Flags.kindIsRuntimePrivate):
      self = .heapGenericLocalVariable
    case 128, (1 | Flags.kindIsNonType | Flags.kindIsRuntimePrivate):
      self = .errorObject
    default:
      self = .class
    }
  }
    
  private enum Flags {
    static let kindIsNonHeap = 0x200
    static let kindIsRuntimePrivate = 0x100
    static let kindIsNonType = 0x400
  }
}

func kind(_ type: Any.Type) -> Kind? {
  let kind = unsafeBitCast(type, to: UnsafePointer<Int>.self).pointee
  return Kind(kind: kind)
}

func metadataPointerForType(_ type: Any.Type) -> NSNumber? {
  let kind = kind(type)
  switch kind {
  case .struct:
    let structPointer = unsafeBitCast(type, to: UnsafePointer<StructMetadataLayout>.self)
    return structPointer.pointee.descriptorPointer as NSNumber
  default:
    return nil
  }
}

// Precondition: `proto` must be an existential type
// Always returns true if `type` is not a struct, or if `proto` is class bound
func isPossibleConformance(_ type: Any.Type, _ proto: Any.Type) -> Bool {
  let protoKind = kind(proto)
  guard protoKind == .existential else {
    fatalError("Type is not a protocol")
  }

  guard let typeMetadataPointer = metadataPointerForType(type) else {
    return true
  }

  let pointer = unsafeBitCast(
    proto, to: UnsafePointer<ProtocolMetadataLayout>.self
  )
  let classConstrained = (pointer.pointee.flags & 0x80000000) == 0
  guard !classConstrained else {
    print("Does not support class constrained existential types")
    return true
  }

  let rawPointer = UnsafeRawPointer(pointer)
  var protocolPointer = rawPointer.advanced(by: MemoryLayout<ProtocolMetadataLayout>.size)
  var result = true
  for _ in 0..<pointer.pointee.numProtocols {
    let address = protocolPointer.load(as: UInt64.self)
    // Use this to verify the protocol descriptor is correct
//    let descriptorPointer = protocolPointer.load(as: UnsafePointer<ProtocolDescriptor>.self)
//    let namePointer = UnsafeRawPointer(descriptorPointer) + MemoryLayout<ProtocolDescriptor>.offset(of: \.name)! + Int(descriptorPointer.pointee.name)
//    let protocolName = String(cString: namePointer.assumingMemoryBound(to: UInt8.self))
//    print("Name: \(protocolName)")
    result = result && ZConformHelper.contains(typeMetadataPointer, conformingTo: address as NSNumber)
    protocolPointer = protocolPointer.advanced(by: MemoryLayout<UInt64>.size)
  }
  return result
}

public func zconform<T, P>(_ type: T, _ proto: P.Type) -> P? {
  if isPossibleConformance(T.self, proto) {
    return type as? P
  }
  return nil
}
