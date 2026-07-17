--- Module for a synapse accumulator: computes weighted input current from incoming spikes and stored weights ---
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use STD.TEXTIO.all; -- Required for file reading operations
use IEEE.STD_LOGIC_TEXTIO.all; -- Required for reading std_logic values from text files

entity synapse_accumulator is

  generic (
    weight_array_size : integer; -- 784 or 64, depending on whether this accumulator is for the hidden layer or the output layer.
    neuron_idx        : integer;
    weight_file_path  : string
  );

  port (
    clk         : in std_logic;
    rst         : in std_logic;
    input_spike : in std_logic; -- Incoming spike from 1 input in the previous layer. 
    accum_en    : in std_logic; -- Enable signal from controller
    prep_Isyn   : in std_logic; -- Signal coming from controller to accumulator, pointing out that all the input spikes for the current neurons at the current time step are given to the accumulator, and it can prepare the output synaptic current for the LIF neuron.
    I_syn       : out std_logic_vector(31 downto 0) -- Output synaptic current (32-bit)
  );

end synapse_accumulator;

architecture Behavioral of synapse_accumulator is

  signal I_syn_internal : signed(31 downto 0) := (others => '0'); -- Internal signal for the accumulated synaptic current.

  -- Type of the signal to store the weights read from the file. These are the weights only for 1 neuron. We create the signal after the impure function.
  type weight_array is array (0 to weight_array_size - 1) of std_logic_vector(7 downto 0);

  ---------------------Impure function to access the weight_array type and generics and load the weights in BRAM by reading the file----------------------------
  impure function load_weights return weight_array is

    file text_file      : text; -- File variable for reading the spike patterns
    variable text_line  : line; -- Variable to hold each line read from the file
    variable hex_read   : std_logic_vector(7 downto 0); -- Read weights as 8-bit vectors (They are originly written as 2-bit hex to be read with hread)
    variable buffer_idx : integer := 0; -- Index to keep track of where we are in the memory buffer

    variable local_weights_buffer : weight_array := (others => (others => '0')); -- A buffer inside the function for storing the weights.

  begin

    -- Open the weights file in read mode
    file_open(text_file, weight_file_path, read_mode);

    -- Skip the lines in the file to reach to the point where the respective (ith) neuron's weights start.
    for i in 0 to neuron_idx * weight_array_size - 1 loop
      readline(text_file, text_line);
    end loop;

    -- Starting at the current line, start reading the weights.
    while not endfile(text_file) and buffer_idx < weight_array_size loop

      readline(text_file, text_line);
      hread(text_line, hex_read);

      local_weights_buffer(buffer_idx) := hex_read;
      buffer_idx                       := buffer_idx + 1;

    end loop;
    file_close(text_file);

    return local_weights_buffer; -- Return the loaded weights.

  end function;
  ---------------------------------------------------------------------------------------------------------------------------------------------------------

  -- Right after compiling the impure function we can creat a signal and initialize it using the function call. This keeps the weight loading process to happen only once before the process starts.
  signal weights : weight_array := load_weights;

begin
  ------------------------------------------------
  --- process to compute the synaptic current. ---
  ------------------------------------------------
  process (clk, rst)
    variable weights_idx : integer range 0 to weight_array_size - 1 := 0; -- Variable to index into the weights array.

  begin

    if rst = '1' then
      I_syn_internal <= (others => '0');
      I_syn          <= (others => '0');
      weights_idx := 0;

    elsif rising_edge(clk) then

      -- Only accumulate synaptic current when the controller has not yet signaled that all inputs are given.
      if prep_Isyn = '0' then
        if accum_en = '1' then -- Only run when the layer is active
          if input_spike = '1' then -- Removed the zero check for weights, since it only forces the synthesizer to build more LUTs for bit-by-bit checks. Zero addition is cost free in FPGA.

            -- If there is an incoming spike and the weight is non-zero, accumulate the synaptic current.
            I_syn_internal <= I_syn_internal + signed(weights(weights_idx));

          end if;

          if weights_idx < weight_array_size - 1 then
            weights_idx := weights_idx + 1; -- Increment the weight index for each incoming spike.
          end if;

        end if;
      else
        -- When the controller signals that all inputs are given (prep_Isyn = '1'), prepare the output synaptic current for the LIF neuron in the next clock cycle.
        I_syn <= std_logic_vector(I_syn_internal); -- At this point we are at HIDDEN_ISYN_READY state.

        -- reset the internal synaptic current and weight index for the next round of accumulation.
        I_syn_internal <= (others => '0');
        weights_idx := 0;

      end if;
    end if;
  end process;

end Behavioral;