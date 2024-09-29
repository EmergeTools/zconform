# ZConform

A replacement for `as?` which runs in constant time instead of O(n) when the conformance is not satisfied.

## How it works

ZConform does a one-time scan of all conformances when intialized with `ZConformHelper.setup()`. This populates a cache that can quickly verify if there are no conformances for a type/protocol pair. See the [blog post](https://emergetools.com/blog/posts/SwiftProtocolConformance) for more details.

There is also a POC of replacing the swift runtime implementation with a faster cached version, so it works without needing to call setup and replaces existing as? calls: https://github.com/EmergeTools/zconform/pull/1

## When to use it

If you have many `as?` casts for different type/protocols and have many (thousands) of conformances in your app, the runtime's default conformance check doesn't work well. It will do a linear scan of all conformances each time a new type/protocol combination is checked. If you know not all the casts will be successful ZConform likely speeds up your app since it can avoid the O(n) operation entirely.

## Limitations

This implementation is not production ready. It builds the cache as new images are loaded with `_dyld_register_func_for_add_image` but doesn't have any safeguards if this cache update is performed while a conformance check is ongoing on a different thread. It's also not supporting class bound protocols, and only supports checking conformance of structs. Objective-C bridging also would require a separate implementation, it only works with types defined purely in Swift.

If you‘re interested in productionizing this in your app, please [get in touch](mailto:team@emergetools.com)
