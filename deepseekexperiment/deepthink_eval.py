import numpy as np

def relu(x):
    return np.maximum(0, x)

print("=== DEEP THINK: THE 'SQUEEZE' EVALUATION ===")

hidden_dim = 7168
num_experts = 384

# DeepSeek usually activates 8 experts
ideal_k = 8

# Simulate orthogonal experts
experts = np.random.randn(num_experts, hidden_dim) / np.sqrt(hidden_dim)
token = np.random.randn(hidden_dim)
gate = np.random.randn(num_experts, hidden_dim) / np.sqrt(hidden_dim)

# Get probabilities
logits = token @ gate.T
probs = relu(logits)
# Normalize top K probs like DeepSeek does
sorted_indices = np.argsort(probs)[::-1]

# Function to get output for Top K
def get_top_k_output(k):
    indices = sorted_indices[:k]
    output = np.zeros(hidden_dim)
    
    # DeepSeek normalizes the weights of the chosen experts so they sum to 1.0 (or similar scaling)
    chosen_probs = probs[indices]
    if np.sum(chosen_probs) > 0:
        chosen_probs = chosen_probs / np.sum(chosen_probs)
        
    for i, idx in enumerate(indices):
        output += experts[idx] * chosen_probs[i]
    return output

ideal_output = get_top_k_output(ideal_k)
top_4_output = get_top_k_output(4)
top_2_output = get_top_k_output(2)
top_1_output = get_top_k_output(1)

def cosine_similarity(a, b):
    mag_a = np.linalg.norm(a)
    mag_b = np.linalg.norm(b)
    if mag_a == 0 or mag_b == 0: return 0.0
    return np.dot(a, b) / (mag_a * mag_b)

sim_4 = cosine_similarity(ideal_output, top_4_output)
sim_2 = cosine_similarity(ideal_output, top_2_output)
sim_1 = cosine_similarity(ideal_output, top_1_output)

print(f"Top-4 'Squeeze' Retains:  {sim_4 * 100:.2f}% of original intelligence")
print(f"Top-2 'Squeeze' Retains:  {sim_2 * 100:.2f}% of original intelligence")
print(f"Top-1 'Squeeze' Retains:  {sim_1 * 100:.2f}% of original intelligence")
