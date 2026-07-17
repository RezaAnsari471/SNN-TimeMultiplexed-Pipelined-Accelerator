# ---- SNN model with Energy/Power Profiling ----
import os
import time
import numpy as np

# load the quantized weights from the .npy files for hidden and output layers
print("\n--- Loading Weights, Spike Patterns and Labels ---")
current_folder = os.path.dirname(os.path.abspath(__file__))
hidden_weights_path = os.path.join(current_folder, 'w_hidden_int8.npy')
output_weights_path = os.path.join(current_folder, 'w_output_int8.npy')
w_hidden = np.load(hidden_weights_path)
w_output = np.load(output_weights_path)
print(f"----------------------------------------------------------")
print(f"Size of the hidden layer: {w_hidden.shape[0]} | shape: {w_hidden.shape} \nSize of the output layer: {w_output.shape[0]} | shape: {w_output.shape}")

# load the spike patterns from the .npy file
spike_patterns_path = os.path.join(current_folder, 'spike_patterns.npy')
spike_patterns = np.load(spike_patterns_path) # Shape: (num_samples, time_steps (T), 784 for MNIST)
T = spike_patterns.shape[1]  # Number of time steps
num_samples = spike_patterns.shape[0]
print(f"Number of input neurons: {spike_patterns.shape[2]}")
print(f"Number of time steps (T): {T}")
print(f"Number of samples: {num_samples}")

# load the labels from the .npy file
labels_path = os.path.join(current_folder, 'labels.npy')
labels = np.load(labels_path)

# ----------------------------------Define the SNN parameters--------------------------------
num_repeats = 1 # set to 10 or higher for more accurate runtime and power measurments, however for the Accuracy measurments stick with 1
theta = 450  # θ: Threshold for spiking
leak_shift = 6  # Shift for leaky integration (equivalent to dividing by 2^(leak_shift))
print(f"SNN Parameters: Threshold (theta) = {theta} | Leak shift = {leak_shift}")
print(f"----------------------------------------------------------")
print("Data loaded and model initialized.")

# -------------------------------- SNN implementation ----------------------------------------

# To match 32-bit hardware accumulators and prevent overflow during matrix math
w_h_32 = w_hidden.astype(np.int32)
w_o_32 = w_output.astype(np.int32)

# Instead of 1D arrays, we use 2D arrays to process all samples at once: shape (num_samples, neurons)
hidden_potentials = np.zeros((num_samples, w_h_32.shape[0]), dtype=np.int32)
output_potentials = np.zeros((num_samples, w_o_32.shape[0]), dtype=np.int32)
output_spike_counts = np.zeros((num_samples, w_o_32.shape[0]), dtype=np.int32)

# --- THE FIRST GATE: PAUSE FOR HWINFO ---
# print("==========================================================")
# print("1. Open HWInfo64 Sensors Window.")
# print("2. Locate 'CPU Package Power'.")
# print("3. Click the 'Reset' (Clock) button at the bottom right.")
# print("==========================================================")
# input("--> Once HWInfo64 is reset, press ENTER here to start SNN inference...")

start_time = time.perf_counter()
# --------------------------------------SNN Runtime-------------------------------------------

# Transpose spike_patterns to shape (T, num_samples, 784) for faster temporal iteration
# Cast to int32 to match our accumulators during dot product
spike_patterns_t = spike_patterns.transpose(1, 0, 2).astype(np.int32)

print(f"\nRunning SNN inference on {num_samples} samples x {num_repeats} repetitions...")

for repeat in range(num_repeats):

    # The ONLY loop we keep is the temporal one, preserving the LIF dynamics
    for t in range(T):

        # Get all 1000 input patterns for the current time step simultaneously
        input_spikes = spike_patterns_t[t] # Shape: (num_samples, 784) - each row is the input spike pattern for one sample at time t
        
        # --- HIDDEN LAYER ---
        # Matrix multiplication replaces the nested i and j weight loops
        I_syn_hidden = input_spikes @ w_h_32.T # [1000, 64] = [1000, 784] @ [784, 64]
        
        # Leaky integration using bitwise right-shift (matches VHDL ">>" operator)
        hidden_potentials = hidden_potentials - (hidden_potentials >> leak_shift) + I_syn_hidden
        
        # Vectorized threshold evaluation
        hidden_spikes = (hidden_potentials >= theta).astype(np.int32)
        
        # Reset membrane potentials to 0 where a spike occurred
        hidden_potentials[hidden_spikes == 1] = 0
        
        # --- OUTPUT LAYER ---
        I_syn_output = hidden_spikes @ w_o_32.T
        
        output_potentials = output_potentials - (output_potentials >> leak_shift) + I_syn_output
        
        output_spikes = (output_potentials >= theta).astype(np.int32)
        output_spike_counts += output_spikes # [1000, 10] = [1000, 10] + [1000, 10]
        
        output_potentials[output_spikes == 1] = 0

    # --- VECTORIZED READOUT & TIE-BREAKER ---
    # Sum the total spikes for each sample to find dead-locks
    total_output_spikes = np.sum(output_spike_counts, axis=1)

    # Find the argmax for both conditions across the whole batch
    pred_potentials = np.argmax(output_potentials, axis=1)
    pred_spikes = np.argmax(output_spike_counts, axis=1)

    # If total spikes == 0, use potentials, otherwise use spikes
    predicted_labels = np.where(total_output_spikes == 0, pred_potentials, pred_spikes)

    # Sum up all correct predictions instantly
    correct_predictions = np.sum(predicted_labels == labels)           
# -------------------------------------------------------------------------------------------------
end_time = time.perf_counter()
core_runtime_sec = end_time - start_time

print(f"----------------------------------------------------------")
print(f"Correct predictions: {correct_predictions} out of {num_samples} | Accuracy: {correct_predictions/num_samples*100:.2f}%")
print(f"Average time for a SINGLE {num_samples} run: {core_runtime_sec / num_repeats:.4f} seconds")
print(f"----------------------------------------------------------")
# print("Read the 'Average' column for 'CPU Package Power'.")