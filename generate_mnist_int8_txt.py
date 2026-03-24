import argparse
from pathlib import Path

import torch
from torchvision import datasets


IMG_H = 28
IMG_W = 28
IMG_SIZE = IMG_H * IMG_W
INT8_MIN = -128
INT8_MAX = 127


def quantize_for_accelerator(x: torch.Tensor, scale: float, zero_point: int) -> torch.Tensor:
    """
    Functional definition:
    Quantize normalized float input x into the signed 8-bit integer domain
    expected by the accelerator.

        q = round(x / scale) + zero_point

    The result is then range-checked against signed int8.

    Input:
        x          : float tensor, expected range [0, 1]
        scale      : positive float
        zero_point : integer

    Output:
        q_int8     : tensor with dtype torch.int8
    """
    if scale <= 0.0:
        raise ValueError(f"scale must be > 0, got {scale}")

    q = torch.round(x / scale) + zero_point
    q = q.to(torch.int32)

    qmin = int(q.min().item())
    qmax = int(q.max().item())
    if qmin < INT8_MIN or qmax > INT8_MAX:
        raise ValueError(
            "Quantized input does not fit signed int8 range required by accelerator: "
            f"min={qmin}, max={qmax}, allowed=[{INT8_MIN}, {INT8_MAX}]"
        )

    return q.to(torch.int8)


def image_to_quantized_vector(img_f32: torch.Tensor, scale: float, zero_point: int) -> torch.Tensor:
    """
    Convert one [28,28] normalized MNIST image into a flattened 784-element int8 vector.
    """
    if tuple(img_f32.shape) != (IMG_H, IMG_W):
        raise ValueError(f"Expected image shape {(IMG_H, IMG_W)}, got {tuple(img_f32.shape)}")

    q_img = quantize_for_accelerator(img_f32, scale, zero_point)
    return q_img.reshape(IMG_SIZE)


def save_image_txt(path: Path, images_q: list[torch.Tensor]) -> None:
    """
    Write one image per line, 784 signed decimal integers per line.
    """
    with path.open("w", encoding="utf-8") as f:
        for vec in images_q:
            if vec.numel() != IMG_SIZE:
                raise ValueError(f"Each image must have {IMG_SIZE} elements, got {vec.numel()}")
            f.write(" ".join(str(int(v)) for v in vec.tolist()) + "\n")


def save_label_txt(path: Path, labels: list[int]) -> None:
    """
    Write one label per line.
    """
    with path.open("w", encoding="utf-8") as f:
        for lbl in labels:
            f.write(f"{int(lbl)}\n")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate signed-int8 MNIST text files for accelerator inference."
    )

    parser.add_argument(
        "--scale",
        type=float,
        default=0.0079,
        help="Input quantization scale"
    )
    parser.add_argument(
        "--zero_point",
        type=int,
        default=0,
        help="Input quantization zero point"
    )
    parser.add_argument(
        "--start_idx",
        type=int,
        default=0,
        help="Start index in MNIST test set"
    )
    parser.add_argument(
        "--num_images",
        type=int,
        default=100,
        help="Number of images to export"
    )
    parser.add_argument(
        "--out_img_txt",
        type=str,
        default="mnist_int8_100.txt",
        help="Output image text file"
    )
    parser.add_argument(
        "--out_lbl_txt",
        type=str,
        default="mnist_label_100.txt",
        help="Output label text file"
    )
    parser.add_argument(
        "--data_root",
        type=str,
        default="./mnist_data",
        help="Directory for torchvision MNIST download/cache"
    )

    args = parser.parse_args(argv)

    if args.zero_point < INT8_MIN or args.zero_point > INT8_MAX:
        raise ValueError(
            f"zero_point must fit signed int8 range [{INT8_MIN}, {INT8_MAX}], got {args.zero_point}"
        )
    if args.num_images <= 0:
        raise ValueError(f"num_images must be > 0, got {args.num_images}")
    if args.start_idx < 0:
        raise ValueError(f"start_idx must be >= 0, got {args.start_idx}")

    out_img_txt = Path(args.out_img_txt)
    out_lbl_txt = Path(args.out_lbl_txt)
    out_img_txt.parent.mkdir(parents=True, exist_ok=True)
    out_lbl_txt.parent.mkdir(parents=True, exist_ok=True)

    # Load MNIST test set
    mnist_test = datasets.MNIST(
        root=str(Path(args.data_root)),
        train=False,
        download=True,
    )

    # Must match training/inference preprocessing exactly
    x_test = mnist_test.data.float() / 255.0
    y_test = mnist_test.targets

    total_available = len(x_test)
    end_idx = args.start_idx + args.num_images

    if end_idx > total_available:
        raise ValueError(
            f"Requested images [{args.start_idx}, {end_idx - 1}] "
            f"but test set contains only {total_available} images"
        )

    images_q: list[torch.Tensor] = []
    labels: list[int] = []

    for i in range(args.start_idx, end_idx):
        img_f32 = x_test[i]
        label = int(y_test[i])

        q_vec = image_to_quantized_vector(
            img_f32=img_f32,
            scale=args.scale,
            zero_point=args.zero_point,
        )

        images_q.append(q_vec)
        labels.append(label)

    save_image_txt(out_img_txt, images_q)
    save_label_txt(out_lbl_txt, labels)

    print(f"Saved image file : {out_img_txt}")
    print(f"Saved label file : {out_lbl_txt}")
    print(f"Start index      : {args.start_idx}")
    print(f"Images exported  : {args.num_images}")
    print(f"Scale            : {args.scale}")
    print(f"Zero point       : {args.zero_point}")

    # Sanity print for first exported sample
    first = images_q[0]
    print(f"First exported label    : {labels[0]}")
    print(f"First 16 q pixels       : {first[:16].tolist()}")
    print(f"First exported q min/max: {int(first.min())} / {int(first.max())}")


if __name__ == "__main__":
    main()
