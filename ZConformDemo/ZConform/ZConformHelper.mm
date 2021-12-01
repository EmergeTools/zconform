//
//  zconform.m
//  ZConform
//
//  Created by Noah Martin on 11/25/21.
//

#import <Foundation/Foundation.h>
#import <mach-o/getsect.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/ldsyms.h>
#include <unordered_map>
#include <unordered_set>

#import "ZConformHelper.h"

#define DEBUG_PROTOCOL_NAMES 0

struct ProtocolDescriptor {
  uint32_t flags;
  uint32_t parent;
  int32_t name;
};

// https://github.com/apple/swift/blob/main/include/swift/ABI/MetadataValues.h#L372-L398
uint32_t TypeReferenceKindDirectTypeDescriptor = 0;
uint32_t TypeReferenceKindIndirectTypeDescriptor = 1;

// https://github.com/apple/swift/blob/main/include/swift/ABI/MetadataValues.h#L582-L687
#define TypeMetadataKindShift 3;
uint32_t TypeMetadataKindMask = 0x7 << TypeMetadataKindShift;

struct ProtocolConformanceDescriptor {
  int32_t protocolDescriptor;
  int32_t nominalTypeDescriptor;
  int32_t protocolWitnessTable;
  uint32_t conformanceFlags;
};

std::unordered_map<uint64_t, std::unordered_set<uint64_t>> cache;

void setupImage(const struct mach_header *header, intptr_t slide) {
  unsigned long size = 0;
  int32_t *sectionPointer = (int32_t *) getsectiondata(
    (struct mach_header_64 *) header,
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
      } else {
        #if DEBUG_PROTOCOL_NAMES
        printf("Unhandled reference kind %d %s\n", referenceKind, name);
        #endif
      }
      if (typePointer) {
        auto result = cache.find(key);
        if (result == cache.end()) {
          std::unordered_set<uint64_t> val = { typePointer };
          cache.insert ( {key,val} );
        } else {
          result->second.insert(typePointer);
        }
      }
      sectionPointer = sectionPointer + 1;
    }
  }
}

static void setup() {
  // This could be problematic if a protocol conformance is checked
  // on a background thread while a new image is being loaded.
  _dyld_register_func_for_add_image(setupImage);
}

@implementation ZConformHelper

+ (void)setup {
  setup();
}

+ (BOOL)contains:(NSNumber * _Nonnull)address conformingTo:(NSNumber * _Nonnull)protocolAddress {
  auto result = cache.find(protocolAddress.unsignedLongLongValue);
  if (result == cache.end()) {
    return NO;
  }
  return result->second.find(address.unsignedLongLongValue) != result->second.end();
}

@end
