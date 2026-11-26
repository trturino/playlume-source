---
tags:
- depth-estimation
library_name: coreml
license: apache-2.0
---

# Depth Anything Core ML Models

Depth Anything model was introduced in the paper [Depth Anything: Unleashing the Power of Large-Scale Unlabeled Data](https://arxiv.org/abs/2401.10891) by Lihe Yang et al. and first released in [this repository](https://github.com/LiheYoung/Depth-Anything).

## Model description

Depth Anything leverages the [DPT](https://huggingface.co/docs/transformers/model_doc/dpt) architecture with a [DINOv2](https://huggingface.co/docs/transformers/model_doc/dinov2) backbone.

The model is trained on ~62 million images, obtaining state-of-the-art results for both relative and absolute depth estimation.

<img src="https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/transformers/model_doc/depth_anything_overview.jpg"
alt="drawing" width="600"/>

<small> Depth Anything overview. Taken from the <a href="https://arxiv.org/abs/2401.10891">original paper</a>.</small>

## Evaluation - Variants

| Variant                                                 | Parameters | Size (MB) | Weight precision | Act. precision | abs-rel error | abs-rel reference |
| ------------------------------------------------------- | ---------: | --------: | ---------------- | -------------- | ------------: | ----------------: |
| [small-original](https://huggingface.co/LiheYoung/depth-anything-small-hf) (PyTorch)                                 |      24.8M |      99.2 | Float32          | Float32        |               |                   |
| [DepthAnythingSmallF32](DepthAnythingSmallF32.mlpackage) |      24.8M |      99.0 | Float32          | Float32        |        0.0073 |    small-original |
| [DepthAnythingSmallF16](DepthAnythingSmallF16.mlpackage) |      24.8M |      45.8 | Float16          | Float16        |        0.0077 |    small-original |

## Evaluation - Inference time

The following results use the small-float16 variant.

| Device               | OS   | Inference time (ms) | Dominant compute unit |
| -------------------- | ---- | ------------------: | --------------------- |
| iPhone 12 Pro Max    | 18.0 |               31.10 | Neural Engine         |
| iPhone 15 Pro Max    | 17.4 |               33.90 | Neural Engine         |
| MacBook Pro (M1 Max) | 15.0 |               32.80 | Neural Engine         |
| MacBook Pro (M3 Max) | 15.0 |               24.58 | Neural Engine         |


## Download

Install `huggingface-cli`

```bash
brew install huggingface-cli
```

To download one of the `.mlpackage` folders to the `models` directory:

```bash
huggingface-cli download \
  --local-dir models --local-dir-use-symlinks False \
  apple/coreml-depth-anything-small \
  --include "DepthAnythingSmallF16.mlpackage/*"
```

To download everything, skip the `--include` argument.

## Integrate in Swift apps

The [`huggingface/coreml-examples`](https://github.com/huggingface/coreml-examples/blob/main/depth-anything-example/README.md) repository contains sample Swift code for `coreml-depth-anything-small` and other models. See [the instructions there](https://github.com/huggingface/coreml-examples/tree/main/depth-anything-example) to build the demo app, which shows how to use the model in your own Swift apps.
