//
//  Initializer.m
//  ZConform
//
//  Created by Noah Martin on 3/23/24.
//

#import "AppDelegate.h"
#import "fishhook.h"
#import <objc/runtime.h>
#include <stdio.h>
#include <mach-o/getsect.h>
#include <mach-o/dyld.h>

#include <unordered_map>
#include <unordered_set>

#define DEBUG_PROTOCOL_NAMES 0


struct ProtocolDescriptor {
  uint32_t flags;
  int32_t parent;
  int32_t name;
};

struct TargetModuleContextDescriptor {
  uint32_t flags;
  int32_t parent;
  int32_t name;
};

struct TargetClassDescriptor {
  uint32_t flags;
  int32_t parent;
  int32_t name;
  int32_t accessFunction;
  int32_t fieldDescriptor;
  int32_t superclassType;
  // ... more
};

// Define ProtocolConformanceDescriptor
struct ProtocolConformanceDescriptor {
    /// The protocol to which the conformance applies.
    int32_t protocolDescriptor;

    /// The type that conforms to the protocol.
  int32_t nominalTypeDescriptor;

    /// A pointer to the witness table for the conformance.
  int32_t protocolWitnessTable;

  uint32_t conformanceFlags;
};

enum _dyld_protocol_conformance_result_kind {
  _dyld_protocol_conformance_result_kind_found_descriptor,
  _dyld_protocol_conformance_result_kind_found_witness_table,
  _dyld_protocol_conformance_result_kind_not_found,
  _dyld_protocol_conformance_result_kind_definitive_failure
  // Unknown values will be considered to be a non-definitive failure, so we can
  // add more response kinds later if needed without a synchronized submission.
};

struct _dyld_protocol_conformance_result {
    // Note this is really a _dyld_protocol_conformance_result_kind in disguise
    uintptr_t kind;

    // Contains a ProtocolConformanceDescriptor iff `kind` is _dyld_protocol_conformance_result_kind_found_descriptor
    // Contains a WitnessTable iff `kind` is _dyld_protocol_conformance_result_kind_found_witness_table
    const void *value;
};

// https://github.com/apple/swift/blob/main/include/swift/ABI/MetadataValues.h#L372-L398
uint32_t TypeReferenceKindDirectTypeDescriptor = 0;
uint32_t TypeReferenceKindIndirectTypeDescriptor = 1;
uint32_t TypeReferenceKindDirectObjCClassName = 2;

// https://github.com/apple/swift/blob/main/include/swift/ABI/MetadataValues.h#L582-L687
#define TypeMetadataKindShift 3;
uint32_t TypeMetadataKindMask = 0x7 << TypeMetadataKindShift;

std::unordered_map<uint64_t, std::unordered_map<uint64_t, uint64_t> *> *cache;

// https://github.com/apple-oss-distributions/dyld/blob/d1a0f6869ece370913a3f749617e457f3b4cd7c4/common/OptimizerSwift.cpp#L462
static void find_conformances_in_image(const struct mach_header_64 *header) {
  unsigned long size = 0;
  int32_t *sectionPointer = (int32_t *) getsectiondata(
    header,
    "__TEXT",
    "__swift5_proto",
    &size);
  struct ProtocolDescriptor *proto;
  if (size) {
    for (int i = 0; i < size/4; i++) {
      struct ProtocolConformanceDescriptor *conformance = (struct ProtocolConformanceDescriptor *) (((char *) sectionPointer) + (*((int32_t *) sectionPointer)));
      if ((conformance->protocolDescriptor & 0x1) == 1) {
        // Indirect pointer
        uint64_t *ptr = (uint64_t *) (((char *) conformance) + (conformance->protocolDescriptor & ~1));
        proto = (struct ProtocolDescriptor *) *ptr;
      } else {
        proto = (struct ProtocolDescriptor *) (((char *) conformance) + conformance->protocolDescriptor);
      }
      #if DEBUG_PROTOCOL_NAMES
      char *name = (((char *) proto) + 8 + proto->name);
      printf("Protocol named: %s\n", name);
      #endif
      uint64_t key = (uint64_t) proto;
      UInt32 referenceKind = (conformance->conformanceFlags & TypeMetadataKindMask) >> TypeMetadataKindShift;
      uint64_t typePointer = 0;
      if (referenceKind == TypeReferenceKindIndirectTypeDescriptor) {
        typePointer = *((uint64_t *) (((char *) conformance) + 4 + conformance->nominalTypeDescriptor));
      } else if (referenceKind == TypeReferenceKindDirectTypeDescriptor) {
        typePointer = (uint64_t) (((char *) conformance) + 4 + conformance->nominalTypeDescriptor);
      } else if (referenceKind == TypeReferenceKindDirectObjCClassName) {
        char *name = (((char *) conformance) + 4 + conformance->nominalTypeDescriptor);
        Class metaClass = objc_getClass(name);
        typePointer = (uint64_t) metaClass;
      } else {
        #if DEBUG_PROTOCOL_NAMES
        printf("Unhandled reference kind %d %s\n", referenceKind, name);
        #endif
      }
      if (typePointer) {
        auto result = cache->find(key);
        if (result == cache->end()) {
          std::unordered_map<uint64_t, uint64_t> *val = new std::unordered_map<uint64_t, uint64_t>();
          val->insert({typePointer, (uint64_t) conformance});
          cache->insert ( {key,val} );
        } else {
          result->second->insert({typePointer, (uint64_t) conformance});
        }
      }
      sectionPointer = sectionPointer + 1;
    }
  }
}

static struct _dyld_protocol_conformance_result (*original_dyld_find_protocol_conformance_on_disk)(const void *protocolDescriptor,
                                                                                                   const void *metadataType,
                                                                                                   const void *typeDescriptor,
                                                                                                   uint32_t flags);
struct _dyld_protocol_conformance_result hooked_dyld_find_protocol_conformance_on_disk(const void *protocolDescriptor,
                                                                                       const void *metadataType,
                                                                                       const void *typeDescriptor,
                                                                                       uint32_t flags) {
  struct _dyld_protocol_conformance_result result;

  auto cacheResult = cache->find((uint64_t) protocolDescriptor);

  if (cacheResult != cache->end()) {
    auto set = cacheResult->second;
    if (typeDescriptor) {
      auto conformance = set->find((uint64_t) typeDescriptor);
      if (conformance != set->end()) {
        result.kind = _dyld_protocol_conformance_result_kind_found_descriptor;
        result.value = (const void *) conformance->second;
        return result;
      }
    }

    if (metadataType) {
      auto conformance = set->find((uint64_t) metadataType);
      if (conformance != set->end()) {
        result.kind = _dyld_protocol_conformance_result_kind_found_descriptor;
        result.value = (const void *) conformance->second;
        return result;
      }
    }
  }

  if (typeDescriptor) {
    struct TargetModuleContextDescriptor *type = (struct TargetModuleContextDescriptor *) typeDescriptor;
    auto kind = type->flags & 0x1F;
    // Struct or enum
    if (kind == 17 || kind == 18) {
        result.kind = _dyld_protocol_conformance_result_kind_definitive_failure;
        return result;
    // Class
    } else if (kind == 16) {
      auto classDesc = (struct TargetClassDescriptor *) typeDescriptor;
      if (classDesc->superclassType == 0) {
        result.kind = _dyld_protocol_conformance_result_kind_definitive_failure;
        return result;
      }
    // Protocol
    } else if (kind == 3) {
      result.kind = _dyld_protocol_conformance_result_kind_definitive_failure;
      return result;
    }
  } else if (metadataType) {
    Class test = (__bridge Class) metadataType;
    Class superClass = class_getSuperclass(test);
    if (!superClass) {
      result.kind = _dyld_protocol_conformance_result_kind_definitive_failure;
      return result;
    }
  }
  result = original_dyld_find_protocol_conformance_on_disk(protocolDescriptor, metadataType, typeDescriptor, flags);
  return result;
}

void setupImage(const struct mach_header *header, intptr_t slide) {
  find_conformances_in_image((mach_header_64 *) header);
}


__attribute__((constructor)) void SetupZConform(void);
void SetupZConform(void) {
  cache = new std::unordered_map<uint64_t, std::unordered_map<uint64_t, uint64_t> *>();
  _dyld_register_func_for_add_image(setupImage);
  rebind_symbols((struct rebinding[1]){{"_dyld_find_protocol_conformance_on_disk", (void**)hooked_dyld_find_protocol_conformance_on_disk, (void**)&original_dyld_find_protocol_conformance_on_disk }}, 1);
}
