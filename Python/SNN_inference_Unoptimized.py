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
num_repeats = 1 # set to 10 or higher for more accurate runtime and power measurments, however for accuracy measurments stick with 1
theta = 450  # θ: Threshold for spiking
leak_shift = 6  # Shift for leaky integration (equivalent to dividing by 2^(leak_shift))
print(f"SNN Parameters: Threshold (theta) = {theta} | Leak shift = {leak_shift}")
print(f"----------------------------------------------------------")
print("Data loaded and model initialized.")
# -------------------------------- SNN implementation ----------------------------------------

# Pre-allocate arrays to hold the membrane potentials and spikes of hidden and output neurons
hidden_potentials = np.zeros((w_hidden.shape[0]), dtype=np.int32)
output_potentials = np.zeros((w_output.shape[0]), dtype=np.int32)
hidden_spikes = np.zeros((w_hidden.shape[0]))
output_spike_counts = np.zeros(w_output.shape[0], dtype=np.int8)

# To evaluate the SNN accuracy, we will run a loop over all the samples.
correct_predictions = 0
predicted_labels = np.zeros(labels.shape[0], dtype=np.int8)

# --- THE FIRST GATE: PAUSE FOR HWINFO ---
print("==========================================================")
print("1. Open HWInfo64 Sensors Window.")
print("2. Locate 'CPU Package Power'.")
print("3. Click the 'Reset' (Clock) button at the bottom right.")
print("==========================================================")
input("--> Once HWInfo64 is reset, press ENTER here to start SNN inference...")

start_time = time.perf_counter()
# --------------------------------------SNN Runtime-------------------------------------------

print(f"\nRunning SNN inference on {num_samples} samples x {num_repeats} repetitions...")

for repeat in range(num_repeats):

    # Loop over all the samples to evaluate the SNN overall accuracy
    for sample_idx in range(num_samples):
        spike_pattern = spike_patterns[sample_idx]  # Get the spike pattern for the current sample
        label = labels[sample_idx]  # Get the true label for the current sample

        # Reset the membrane potentials and output spikes for the current sample
        hidden_potentials.fill(0)
        output_potentials.fill(0)
        hidden_spikes.fill(0)
        output_spike_counts.fill(0)

        # Loop over all the time steps to simulate the SNN inference for the current sample
        for t in range(T):
            input_spikes = spike_pattern[t]  # Get the spike pattern for the current time step

            # Calculate the hidden neurons' spikes based on the input spikes and weights for each time step
            for i in range(w_hidden.shape[0]):  # For each hidden neuron
                I_syn = 0  # Reset synaptic current for the next hidden neuron

                for j in range(w_hidden.shape[1]):  # For each input connection
                    if input_spikes[j] == 1 and w_hidden[i, j] != 0:  # If there is a spike from the input neuron and the weight is not zero
                        I_syn += w_hidden[i, j].item()  # Synaptic current contribution from the input spike to the hidden neuron.

                hidden_potentials[i] = hidden_potentials[i] - (hidden_potentials[i]//(2**leak_shift)) + I_syn  # The membrane potential V for the hidden layer at time step t.        

                # Check for hidden neuron spikes and reset potentials if they exceed the threshold
                if hidden_potentials[i] >= theta:
                    hidden_spikes[i] = 1  # Record the spike for the hidden neuron at time step t
                    hidden_potentials[i] = 0  # Reset the membrane potential after spiking
                else:
                    hidden_spikes[i] = 0  # No spike for the hidden neuron at time step t

            # Calculate the output neurons' spikes based on the hidden layer's spikes and weights for each time step
            for i in range(w_output.shape[0]):  # For each output neuron
                I_syn = 0

                for j in range(w_output.shape[1]):  # For each hidden neuron connection
                    if hidden_spikes[j] == 1 and w_output[i, j] != 0:  # If there is a spike from the hidden neuron at time t and the weight is not zero

                        I_syn += w_output[i, j].item()  # Synaptic current contribution from the hidden spike to the output neuron

                output_potentials[i] = output_potentials[i] - (output_potentials[i]//(2**leak_shift)) + I_syn  # The membrane potential V for the output layer at time step t.

                # Check for output neuron spikes and reset potentials if they exceed the threshold
                if output_potentials[i] >= theta:
                    output_spike_counts[i] += 1  # Increment the spike count for the output neuron at time step t
                    output_potentials[i] = 0  # Reset the membrane potential after spiking

        # Determine which output neuron has the highest spike count after processing all time steps to make a prediction
        if np.sum(output_spike_counts) == 0: # If none of the output neurons spike
            predicted_label = np.argmax(output_potentials) # neuron with the highest potential gets selected as predicted label
            predicted_labels[sample_idx] = predicted_label
        else:
            predicted_label = np.argmax(output_spike_counts)
            predicted_labels[sample_idx] = predicted_label

        if predicted_label == label:
            correct_predictions += 1            
# -------------------------------------------------------------------------------------------------
end_time = time.perf_counter()
core_runtime_sec = end_time - start_time


print(f"----------------------------------------------------------")
print(f"Correct predictions: {correct_predictions} out of {num_samples} | Accuracy: {correct_predictions/num_samples*100:.2f}%")
print(f"Average time for a SINGLE {num_samples} run: {core_runtime_sec / num_repeats:.4f} seconds")
print(f"----------------------------------------------------------")
print("Read the 'Average' column for 'CPU Package Power'.")