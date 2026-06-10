import json
with open('/mnt/corpus/DeepSeek-V4-Pro/tokenizer.json', 'r') as f:
    d = json.load(f)
print(type(d['model']['vocab']))
print(list(d['model']['vocab'].items())[:5])
