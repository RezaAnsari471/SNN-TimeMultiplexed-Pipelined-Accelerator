--- Module for input spike driver: feeds precomputed MNIST spike trains into the design during simulation ---
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use STD.TEXTIO.all; -- Required for file reading operations
use IEEE.STD_LOGIC_TEXTIO.all; -- Required for reading std_logic values from text files

entity input_spike_driver is

  generic (
    -- File path for the precomputed spike patterns in my PC.
    input_spikes_file_path : string;

    -- Parameters for the spike patterns
    NUM_SAMPLES : integer; -- Number of MNIST samples
    T           : integer  -- Number of time steps for inference
  );

  port (
    clk : in std_logic;
    rst : in std_logic;

    -- Layer Controller pointers to track network state
    sample_idx   : in integer range 0 to NUM_SAMPLES - 1; -- Current MNIST sample index
    timestep_idx : in integer range 0 to T - 1; -- Current timestep T index
    pixel_idx    : in integer range 0 to 783; -- Current pixel index

    -- 1-bit spike output broadcasted to all synapse accumulators
    spike_out : out std_logic
  );

end input_spike_driver;

architecture Behavioral of input_spike_driver is

  -- Total number of bits in the spike file (number of samples * T timesteps * 784 pixels)
  constant total_bits : integer := NUM_SAMPLES * T * 784;
  

  -- Type of the signal to store the spike patterns read from the file. These are the spike inputs only for 1 synapse accumulator. We create the signal after the impure function.
  type flat_spike_array is array (0 to (total_bits - 1)) of std_logic;

  -------------------Impure function to access the flat_spike_array type and generics and load the spike patterns in BRAM by reading the file----------------------------
  impure function load_spike_patterns return flat_spike_array is

    file text_file      : text; -- File variable for reading the spike patterns
    variable text_line  : line; -- Variable to hold each line read from the file
    variable bit_read   : std_logic; -- Variable to hold the std_logic value read from the file (should be '0' or '1')
    variable buffer_idx : integer := 0; -- Index to keep track of where we are in the memory buffer

    variable local_spike_buffer : flat_spike_array := (others => '0'); -- A buffer inside the function for storing the spikes.

  begin

    -- Open the spike file in read mode
    file_open(text_file, input_spikes_file_path, read_mode);

    -- Loop through all the lines and numbers in the file.
    while not endfile(text_file) and buffer_idx < total_bits loop

      readline(text_file, text_line);
      read(text_line, bit_read);

      -- send the read bit to the corresponding position in the memory buffer. 
      -- The buffer index increments with each read bit, filling the buffer sequentially.
      local_spike_buffer(buffer_idx) := bit_read;
      buffer_idx                     := buffer_idx + 1;

    end loop;
    file_close(text_file);

    return local_spike_buffer; -- Return the loaded spikes.

  end function;
  ---------------------------------------------------------------------------------------------------------------------------------------------------------------------

  -- Right after compiling the impure function we can creat a signal and initialize it using the function call. This keeps the spike loading process to happen only once before the process starts.
  signal input_memory_buffer : flat_spike_array := load_spike_patterns;

begin

    -- Instantly maps the incoming pointers to the memory buffer index. This will eliminate any latancy between input spike driver and the synapse accumulators.
    spike_out <= input_memory_buffer((sample_idx * T * 784) + (timestep_idx * 784) + pixel_idx);

end Behavioral;