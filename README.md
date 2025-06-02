### libsup

libsup wants to be a Streaming Unicode Processing library.
It allows to handle Unicode data regardless of the data structure in which it
is stored, whether it is a slice, gap buffer, rope or piece table.

> [!WARNING]
> This project is currently under active development and its usage is not recommended.

### Overview

The core of the library are the interfaces `Iterator` and `FatIterator` from the `code_point` module.

`Iterator` yields only the code point `u21` and it is used for any transformation
algorithm like normalization and case folding.
The transformation algorithms provide an `Iterator` interface themselves, this
allows to concatenate them.

i.e. To obtain a string which is both case folded and normalized one would
create the following pipeline

```
decoder -> code folder -> normalizer -> encoder
```

`FatIterator` yields, in addition to the code point itself, information about its
position in the original data structure and encoding size, this is useful in
segmentation algorithms.

These interfaces come with some performance penalties which
can be overcome by praying the optimizer to do its
[magic](https://quuxplusone.github.io/blog/2021/02/15/devirtualization/),
but this is a trade-off that I am willing to deal with in return for
the additional flexibility it provides.

### Features

- utf8 validation/encoding/decoding
- grapheme segmentation
- case mapping upper/lower/title (not supporting locale specific mappings yet)
- case folding
- normalization
- general category code point info

### Ideas

Things listed here are in random order and might change any time:

- properties/scripts code point info
- word segmentation algorithm
- sentence segmentation algorithm
- line break algorithm
- collation algorithm
- handle special locale case mappings
- make a fast path in nf\*c normalization for qc_nf\*c code points
- make the simd utf8 validation better on aarch64/riscv64
- benchmark the algorithms against zg and icu
- add fuzz testing using icu as the oracle
- utf8 to utf16 converter (with simd?) and vice versa
- export functions with C abi

### Sources

Sources that I used to learn how to do Unicode stuff:

- Unicode Technical Reports https://www.unicode.org/reports/
- zg https://codeberg.org/atman/zg
- Validating UTF-8 In Less Than One Instruction Per Byte https://arxiv.org/abs/2010.03090
    - Example implementation https://github.com/simdutf/simdutf
    - Nice SIMD explanation https://validark.dev/posts/eine-kleine-vectorized-classification/
