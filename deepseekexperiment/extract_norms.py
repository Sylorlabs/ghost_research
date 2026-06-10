import json
import struct
import os

print("Extracting 1D Norm Weights...")
index_path = "/mnt/corpus/DeepSeek-V4-Pro/model.safetensors.index.json"
base_dir = "/mnt/corpus/DeepSeek-V4-Pro"

with open(index_path, 'r') as f:
    idx = json.load(f)

weight_map = idx['weight_map']
norm_keys = [k for k in weight_map.keys() if 'norm' in k]

# Open binary output file
out_path = "distilled_core/norm_weights.bin"
with open(out_path, 'wb') as out_f:
    for key in norm_keys:
        shard_name = weight_map[key]
        shard_path = os.path.join(base_dir, shard_name)
        
        # Read header length
        with open(shard_path, 'rb') as sf:
            header_len = struct.unpack('<Q', sf.read(8))[0]
            header_bytes = sf.read(header_len)
            header = json.loads(header_bytes.decode('utf-8'))
            
            if key not in header:
                continue
                
            tensor_info = header[key]
            # Only extract 1D tensors (Norms)
            if len(tensor_info['shape']) >= 2:
                continue
                
            offsets = tensor_info['data_offsets']
            sf.seek(8 + header_len + offsets[0])
            tensor_bytes = sf.read(offsets[1] - offsets[0])
            
            # Convert BF16 to FP32
            # BF16 is the upper 16 bits of FP32. We can convert by padding with 16 bits of zeros
            if tensor_info.get('dtype') in ('BFLOAT16', 'BF16'):
                fp32_bytes = bytearray()
                for i in range(0, len(tensor_bytes), 2):
                    # BFLOAT16 is little endian in safetensors
                    # FP32: [00 00] (lower 16 bits) + [b1 b2] (upper 16 bits = BF16)
                    fp32_bytes.extend(b'\x00\x00')
                    fp32_bytes.append(tensor_bytes[i])
                    fp32_bytes.append(tensor_bytes[i+1])
                tensor_bytes = bytes(fp32_bytes)
            elif tensor_info.get('dtype') == 'FLOAT16':
                # Rare, but if float16, we need numpy
                import numpy as np
                tensor_bytes = np.frombuffer(tensor_bytes, dtype=np.float16).astype(np.float32).tobytes()
            
            # Write to norm_weights.bin
            # Format: [name_len: u32] [name: bytes] [data_len: u32] [data: bytes]
            name_bytes = key.encode('utf-8')
            out_f.write(struct.pack('<I', len(name_bytes)))
            out_f.write(name_bytes)
            out_f.write(struct.pack('<I', len(tensor_bytes)))
            out_f.write(tensor_bytes)
            
print("Successfully extracted all 1D norms to norm_weights.bin!")
