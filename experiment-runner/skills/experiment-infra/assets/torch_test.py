import torch


def main() -> None:
    print("torch", torch.__version__)
    print("cuda_available", torch.cuda.is_available())
    print("cuda_device_count", torch.cuda.device_count())
    if torch.cuda.is_available():
        x = torch.randn(1024, 1024, device="cuda")
        y = x @ x
        torch.cuda.synchronize()
        print("device", torch.cuda.get_device_name(0))
        print("matmul_mean", float(y.mean().item()))


if __name__ == "__main__":
    main()
