import os
import torch
from torchvision import datasets, transforms
import torch.nn as nn
from torch.utils.data import DataLoader, random_split

# Define the ANN model
class MNIST_ANN(nn.Module):

    # Initialize the ANN model with one hidden layer and one output layer
    def __init__(self):
        super(MNIST_ANN, self).__init__()

        # Hidden layer: 784 inputs -> 64 outputs.
        self.hidden_layer = nn.Linear(784, 64, bias=False)

        # Output layer: 64 inputs -> 10 digit outputs.
        self.output_layer = nn.Linear(64, 10, bias=False)

    #Define the forward pass of the ANN
    def forward(self, images):

        # Feed the 784 input pixel values into the hidden layer. The output x will be 64 numbers.
        x = self.hidden_layer(images)
        
        # Apply ReLU activation: max(0, x)
        x = torch.relu(x)
        
        # Feed the activated signals into the final layer to get 10 digit outputs.
        outputs = self.output_layer(x)
        
        return outputs

# --- TRAINING ---
# Create an instance of the ANN model
model = MNIST_ANN()

# Define the loss function and optimizer
criterion = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(model.parameters(), lr=0.001)

# Download the MNIST dataset and create a DataLoader with 64 batch size for training
mnist_training_data = datasets.MNIST(root='./data', train=True, download=True, transform=transforms.ToTensor()) # mnist_data contains 60,000 training images (28x28 pixels) and their corresponding labels (0-9)

# Split the 60,000 training images into 59,000 for training and 1,000 for SNN validation
torch.manual_seed(42) # Set a fixed random seed for reproducibility of the train/validation split
train_subset, val_subset = random_split(mnist_training_data, [59000, 1000])

# Create the DataLoader using ONLY the 59,000 training subset
train_loader = DataLoader(train_subset, batch_size=64, shuffle=True)

# Train for the number of epochs over the dataset
epochs = 10

print("Training Started on 59,000 samples...")

for epoch in range(epochs):
    running_loss = 0.0
    
    # Loop over every batch of 64 images
    for images, labels in train_loader:
        
        # 1. Clear old gradients
        optimizer.zero_grad()
        
        # 2. Reshape images from (64, 1, 28, 28) to (64, 784) and run forward pass
        images = images.view(images.size(0), -1)
        outputs = model(images)
        
        # 3. Calculate the batch error
        loss = criterion(outputs, labels)
        
        # 4. Run backpropagation
        loss.backward()
        
        # 5. Tweak the weights
        optimizer.step()
        
        # Track the total loss for visualization
        running_loss += loss.item()
        
    # Print status updates after every epoch pass
    average_loss = running_loss / len(train_loader) # running_loss is the sum of 60,000 loss values per epoch. average_loss is the average loss per batch, which is more informative than the total loss.
    print(f"Epoch [{epoch+1}/{epochs}], Loss: {average_loss:.4f}")

print("Training Complete!")

# --- TESTING ---
# Create a DataLoader for the 1,000 validation samples that will be used for SNN inference later
test_loader = DataLoader(val_subset, batch_size=64, shuffle=False)

# Switch model to evaluation mode and turn off gradient calculation memory
model.eval()
correct = 0 # Count of correct predictions
total = 0 # Count of total predictions made (should be 1000 for the validation set)

print("Testing the trained model...")

# Evaluate the model's performance on the test dataset
with torch.no_grad(): # Turn off gradient tracking to save memory
    for images, labels in test_loader:

        # Flatten the test batch
        images = images.view(images.size(0), -1)
        
        # Get raw output scores
        outputs = model(images)
        
        # Choose the digit with the highest score in each row (dim=1) of the output (64 x 10).
        predictions = torch.argmax(outputs, dim=1) # The 64 predicted digits for each batch.
        
        # Track counts
        total += labels.size(0)
        correct += (predictions == labels).sum().item() #Sum up the number of correct predictions in the batch and add to the total correct count.

# Calculate and print the final percentage
accuracy = (correct / total) * 100
print(f"Final Accuracy on the 1000 Validation Images: {accuracy:.2f}%")

# --- Save the trained weights ---
script_dir = os.path.dirname(os.path.abspath(__file__))
save_path = os.path.join(script_dir, 'Ann_weights.pth')
torch.save(model.state_dict(), save_path)
print("Model weights successfully saved to 'Ann_weights.pth'!")

# ----single input MNIST image test----
# image_number = 6 # Change this number to test different images from the test dataset (0-9999)
# Test_image = datasets.MNIST(root='./data', train=False, download=True, transform=transforms.ToTensor())
# single_image, single_label = Test_image[image_number] # Get the image and its label from the test dataset
# print(f"For the image number {image_number + 1}/10,000, Actual label for the single test image: {single_label}")

# Prepare the single image for prediction
# single_image = single_image.view(1, -1) # Reshape from (1, 28, 28) to (1, 784)
# model.eval()
# with torch.no_grad():
#     output = model(single_image)
#     predicted_label = torch.argmax(output, dim=1).item()
# print(f"Predicted label for the single test image: {predicted_label}")