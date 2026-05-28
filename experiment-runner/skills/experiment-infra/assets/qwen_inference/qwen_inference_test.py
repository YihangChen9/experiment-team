import os
import time

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer


MODEL_PATH = "/mnt/data0/hf_models/Qwen/Qwen2.5-7B-Instruct"
QUERY = "What is active inference?"


def main() -> None:
    print("=== QWEN INFERENCE TEST START ===", flush=True)
    print(f"model_path: {MODEL_PATH}", flush=True)
    print(f"query: {QUERY}", flush=True)
    print(f"torch: {torch.__version__}", flush=True)
    print(f"torch_cuda_version: {torch.version.cuda}", flush=True)
    print(f"CUDA_VISIBLE_DEVICES: {os.environ.get('CUDA_VISIBLE_DEVICES', '<unset>')}", flush=True)
    print(f"NVIDIA_VISIBLE_DEVICES: {os.environ.get('NVIDIA_VISIBLE_DEVICES', '<unset>')}", flush=True)
    print(f"cuda_available: {torch.cuda.is_available()}", flush=True)
    if torch.cuda.is_available():
        print(f"cuda_device: {torch.cuda.get_device_name(0)}", flush=True)

    if not os.path.isdir(MODEL_PATH):
        raise FileNotFoundError(f"Model path does not exist: {MODEL_PATH}")

    start = time.time()
    tokenizer = AutoTokenizer.from_pretrained(
        MODEL_PATH,
        trust_remote_code=True,
        local_files_only=True,
    )
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        torch_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float32,
        device_map="cuda:0" if torch.cuda.is_available() else "cpu",
        trust_remote_code=True,
        local_files_only=True,
    )
    print(f"load_seconds: {time.time() - start:.2f}", flush=True)

    messages = [
        {
            "role": "system",
            "content": "You are a concise, accurate research assistant.",
        },
        {"role": "user", "content": QUERY},
    ]
    prompt = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True,
    )
    inputs = tokenizer([prompt], return_tensors="pt").to(model.device)

    gen_start = time.time()
    with torch.inference_mode():
        generated_ids = model.generate(
            **inputs,
            max_new_tokens=32,
            do_sample=False,
            temperature=None,
            top_p=None,
            pad_token_id=tokenizer.eos_token_id,
        )
    new_tokens = generated_ids[:, inputs.input_ids.shape[-1] :]
    answer = tokenizer.batch_decode(new_tokens, skip_special_tokens=True)[0].strip()

    print("=== QWEN INFERENCE TEST SUMMARY ===", flush=True)
    print(f"generation_seconds: {time.time() - gen_start:.2f}", flush=True)
    print(f"answer: {answer}", flush=True)
    print("=== QWEN INFERENCE TEST END ===", flush=True)


if __name__ == "__main__":
    main()
