import json
import struct
import os

for i in range(1, 3):
    path = f"/mnt/corpus/DeepSeek-V4-Pro/model-{i:05d}-of-00064.safetensors"
    if not os.path.exists(path): continue
    
    with open(path, 'rb') as f:
        header_len = struct.unpack('<Q', f.read(8))[0]
        header = json.loads(f.read(header_len).decode('utf-8'))
        
        for k in header.keys():
            if 'layers.0.' in k and k.endswith('.weight'):
                print(k)
