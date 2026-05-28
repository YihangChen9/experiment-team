import os

import torch


def main() -> None:
    print("=== CUDA VISIBLE TEST START ===", flush=True)
    print(f"CUDA_VISIBLE_DEVICES: {os.environ.get('CUDA_VISIBLE_DEVICES', '<unset>')}", flush=True)
    print(f"NVIDIA_VISIBLE_DEVICES: {os.environ.get('NVIDIA_VISIBLE_DEVICES', '<unset>')}", flush=True)
    print(f"torch: {torch.__version__}", flush=True)
    print(f"torch_cuda_version: {torch.version.cuda}", flush=True)
    print(f"cuda_available: {torch.cuda.is_available()}", flush=True)
    print(f"cuda_device_count: {torch.cuda.device_count()}", flush=True)

    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is still not visible to PyTorch")

    print(f"cuda_device_name_0: {torch.cuda.get_device_name(0)}", flush=True)
    x = torch.arange(8, device="cuda")
    y = (x * 2).sum()
    torch.cuda.synchronize()
    print(f"cuda_tensor_sum: {int(y.item())}", flush=True)
    print("=== CUDA VISIBLE TEST END ===", flush=True)


if __name__ == "__main__":
    main()
