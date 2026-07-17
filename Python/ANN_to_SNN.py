import os
import torch
from torchvision import datasets, transforms
import numpy as np
from torch.utils.data import random_split

# --- Quantization of ANN Weights for SNN Deployment ---

# Re-define the exact network structure so PyTorch knows where the weights belong
class MNIST_ANN(torch.nn.Module):
    def __init__(self):
        super(MNIST_ANN, self).__init__()
        self.hidden_layer = torch.nn.Linear(784, 64, bias=False)
        self.output_layer = torch.nn.Linear(64, 10, bias=False)

    def forward(self, images):
        x = self.hidden_layer(images)
        x = torch.relu(x)
        return self.output_layer(x)

# Instantiate the blank architecture
model = MNIST_ANN()

# Load the saved weights from hard drive
current_folder = os.path.dirname(os.path.abspath(__file__))
load_path = os.path.join(current_folder, 'Ann_weights.pth')
model.load_state_dict(torch.load(load_path))
model.eval()

# Extract the raw floating-point weights as NumPy arrays
w_hidden_float = model.hidden_layer.weight.detach().numpy()  # Shape: (64, 784)
w_output_float = model.output_layer.weight.detach().numpy()  # Shape: (10, 64)

print("--- Weights successfully loaded from hard drive ---")
print(f"Hidden layer matrix shape: {w_hidden_float.shape}")
print(f"Output layer matrix shape: {w_output_float.shape}")

# Quantize the weights to 8-bit integers
w_hidden_int8 = np.round(w_hidden_float * 127/np.max(np.abs(w_hidden_float))).astype(np.int8)
w_output_int8 = np.round(w_output_float * 127/np.max(np.abs(w_output_float))).astype(np.int8)

print("\n--- Quantization Complete ---")
print(f"Hidden layer integer range: {w_hidden_int8.min()} to {w_hidden_int8.max()}")
print(f"Output layer integer range: {w_output_int8.min()} to {w_output_int8.max()}")

# Save the quantized weights as binary files for Python SNN to load later
hidden_save_path = os.path.join(current_folder, 'w_hidden_int8.npy')
output_save_path = os.path.join(current_folder, 'w_output_int8.npy')
np.save(hidden_save_path, w_hidden_int8)
np.save(output_save_path, w_output_int8)

# save the quantized weights as .mem files for VHDL to load later
# Prepare flat, 1D arrays for hardware memory alignment
w_hidden_flat = w_hidden_int8.flatten()
w_output_flat = w_output_int8.flatten()

# Export the Hidden Layer Weights to a .mem file
hidden_file_path = os.path.join(current_folder, 'w_hidden.mem')
with open(hidden_file_path, 'w') as f:
    for weight in w_hidden_flat:
        unsigned_val = int(weight) & 0xFF  # Convert to 8-bit Two's Complement representation since we plan to send negative values to hardware
        f.write(f"{unsigned_val:02x}\n")   # Write as a 2-digit hex string compatible with VHDL's memory initialization format

# Export the Output Layer Weights to a .mem file
output_file_path = os.path.join(current_folder, 'w_output.mem')
with open(output_file_path, 'w') as f:
    for weight in w_output_flat:
        unsigned_val = int(weight) & 0xFF
        f.write(f"{unsigned_val:02x}\n")

print("\n--- Quantized Weights Saved ---")
print(f"Saved: {hidden_save_path}")
print(f"Saved: {output_save_path}")
print(f"Saved: {hidden_file_path}")
print(f"Saved: {output_file_path}")

# --- Spike Encoding of Input Images ---

print("\n--- Spike Encoding of Input Images ---")

# Set fixed random seed for reproducibility
np.random.seed(42)

# Download the MNIST dataset: Choose tarin= true for 1000 validation samples for theta and leak shift tuning and use train = false for the 10,000 test samples for final SNN accuracy test
mnist_training_data = datasets.MNIST(root='./data', train=True, download=True, transform=transforms.ToTensor())

# Split the 60,000 training images into 59,000 for training and 1,000 for SNN validation
torch.manual_seed(42) # Set a fixed random seed for reproducibility of the validation split
train_subset, val_subset = random_split(mnist_training_data, [59000, 1000]) # Comment out if using 10,000 test samples

# take either the 1000 validation samples for parameter tuning or the 10,000 test samples for final accuracy evaluation
# --------------------------------------------------------------
num_test_samples = 1000
T = 16  # Number of time steps for the SNN simulation
# --------------------------------------------------------------
spike_patterns = np.empty((num_test_samples, T, 784), dtype=np.int8)  # Pre-allocate an array to hold the spike patterns for each time step
labels = np.empty(num_test_samples, dtype=np.int8)  # To store the true labels of the test samples for later evaluation

for i in range(num_test_samples):
    test_image_tensor, labels[i] = val_subset[i] # Use mnist_training_data[i] instead of val_subset[i] for the final 10,000 test sample evaluation
    test_image = test_image_tensor.numpy()  # Convert tensor to numpy array

    # Flatten the image to a 1D array of pixel intensities
    test_image_flat = test_image.flatten()

    for t in range(T):

        # create a vector of random numbers between 0 and 1 for each pixel
        random_vector = np.random.rand(784)

        # compare the pixel intensities to the random vector to create a binary spike pattern for each time step
        spike_patterns[i, t] = (test_image_flat > random_vector).astype(np.int8)  # this will create a binary 3D matrix of spike patterns for all test samples and time steps

print(f"Generated spike patterns shape for {num_test_samples} samples: {spike_patterns.shape}")

# Save the spike patterns and labels for each sample as a .npy file for Python SNN to load later
spike_npy_path = os.path.join(current_folder, 'spike_patterns.npy')
np.save(spike_npy_path, spike_patterns)
label_npy_path = os.path.join(current_folder, 'labels.npy')
np.save(label_npy_path, labels)

# Save the spike patterns and labels as .mem files for VHDL to load later
spike_mem_path = os.path.join(current_folder, 'spike_patterns.mem')
with open(spike_mem_path, 'w') as f:
    for i in range(num_test_samples):
        for t in range(T):
            for spike_value in spike_patterns[i, t]:
                f.write(f"{spike_value}\n")  # Write each spike (0 or 1) on a new line. This converts the 3D spike pattern array into a long list of binary values that can be read sequentially by VHDL.

label_mem_path = os.path.join(current_folder, 'labels.mem')
with open(label_mem_path, 'w') as f:
    for label in labels:
        unsigned_val = int(label) & 0xF  # Convert to unsigned 4-bit.
        f.write(f"{unsigned_val:1x}\n")  # Write the label as a single hex digit (0-9) on a new line.

print(f"saved: {spike_npy_path}")
print(f"saved: {label_npy_path}")
print(f"saved: {spike_mem_path}")
print(f"saved: {label_mem_path}")
print(f"--- Done! ---")