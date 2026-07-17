--- layer_controller: Finite-state machine for timestep loop, neuron loop, memory addressing and reset. ---
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity layer_controller is

  generic (
    NUM_SAMPLES : integer; -- Number of MNIST samples
    T           : integer; -- Number of time steps for inference
    NUM_NEURONS : integer  -- Number of neurons in the hiddenlayer
  );

  port (
    clk   : in std_logic;
    rst   : in std_logic;
    start : in std_logic; -- Signal to start the SNN processing

    -- Control signals for the input spike driver
    sample_idx   : out integer range 0 to NUM_SAMPLES - 1; -- Current MNIST sample index
    timestep_idx : out integer range 0 to T - 1; -- Current timestep T index
    pixel_idx    : out integer range 0 to 783; -- Current pixel index

    neuron_idx : out integer range 0 to NUM_NEURONS - 1; -- Current neuron index in the hidden layer

    -- Control signal for the synapse accumulators
    prep_Isyn_hidden : out std_logic; -- Signal to the synapse accumulators in the hidden layer to prepare the I_syn. This signal is sent after 784 clock cycles.
    prep_Isyn_output : out std_logic; -- Signal to the synapse accumulators in the output layer to prepare the I_syn. This signal is sent after 64 (NUM_NEURONS) clock cycles.
    en_hidden        : out std_logic; -- Signal to enable hidden synapse accumulators only during the LOAD_HIDDEN_LAYER state.
    en_output        : out std_logic; -- Signal to enable output synapse accumulators only during the LOAD_OUTPUT_LAYER state.

    -- Control signals for the LIF neurons
    en_lif_hidden : out std_logic; -- Signal to enable hidden LIF neurons only during the HIDDEN_LIF_PROCESSING state.
    en_lif_output : out std_logic; -- Signal to enable output LIF neurons only during the OUTPUT_LIF_PROCESSING state.
    rst_V         : out std_logic; -- Reset potential values when we are about to start with a new sample.

    -- Control signals for the output counter
    count_spike_valid : out std_logic := '0'; -- High for exactly 1 cycle when counters should look at spikes
    reset_counter     : out std_logic; -- Signal to the output counter to reset it's internal counter since we are about to start with a new sample

    -- Control signal for the argmax_unit
    calculate_argmax : out std_logic; -- Telling argmax_unit to calculate the predicted label after t = T.

    -- Control signal for the testbench
    prediction_ready : out std_logic -- To signal the testbench that a new sample prediction is ready to be read.

  );

end layer_controller;

architecture Behavioral of Layer_controller is
  -- Define internal signals and variables for the FSM
  signal pixel_counter    : integer range 0 to 783             := 0; -- Counter for pixels in the input layer
  signal neuron_counter   : integer range 0 to NUM_NEURONS - 1 := 0; -- Counter for neurons in the hidden layer
  signal timestep_counter : integer range 0 to T - 1           := 0; -- Counter for timesteps
  signal sample_counter   : integer range 0 to NUM_SAMPLES - 1 := 0; -- Counter for samples

  -- State encoding for the FSM
  type state_type is (IDLE, RESET_STATE, LOAD_HIDDEN_LAYER, LOAD_OUTPUT_LAYER, HIDDEN_ISYN_READY, OUTPUT_ISYN_READY, HIDDEN_LIF_PROCESSING, OUTPUT_LIF_PROCESSING, OUTPUT_SPIKE_COUNTING, ARGMAX_COMPUTING);
  signal current_state : state_type := IDLE;

begin
  -- FSM process to control the flow of the network
  process (clk, rst)
  begin

    if rst = '1' then
      -- Reset all outputs and internal state
      reset_counter    <= '0';
      prediction_ready <= '0';
      rst_V            <= '0';
      current_state    <= IDLE;
      -- reset variables
      pixel_counter    <= 0;
      neuron_counter   <= 0;
      timestep_counter <= 0;
      sample_counter   <= 0;

    elsif rising_edge(clk) then

      case current_state is
        when IDLE =>
          prediction_ready <= '0';

          if start = '1' then
            -- Transition to loading the hidden layer on the first clock cycle
            current_state <= LOAD_HIDDEN_LAYER;
          end if;

        when RESET_STATE =>
          -- Clear the reset signals before moving on to the next sample.
          reset_counter    <= '0';
          rst_V            <= '0';
          prediction_ready <= '0';
          current_state    <= LOAD_HIDDEN_LAYER;

        when LOAD_HIDDEN_LAYER =>

          -- Loop through all pixels for the current sample and timestep - 784 clock cycles.
          if pixel_counter < 783 then
            pixel_counter <= pixel_counter + 1;
          else
            pixel_counter <= 0; -- Reset pixel counter for the next sample and timestep
            current_state <= HIDDEN_ISYN_READY; -- In the next clock cycle, have the I_syn ready to be fed to the hidden neurons.
          end if;

        when LOAD_OUTPUT_LAYER =>
          -- Loop through all neurons in the hidden layer - 64 (NUM_NEURONS) clock cycles.
          if neuron_counter < NUM_NEURONS - 1 then
            neuron_counter <= neuron_counter + 1;
          else
            neuron_counter <= 0; -- Reset neuron counter for the next timestep
            current_state  <= OUTPUT_ISYN_READY;
          end if;

        when HIDDEN_ISYN_READY =>
          current_state <= HIDDEN_LIF_PROCESSING; -- Next clock cycle, the new I_syn is ready and hidden neurons can use it.

        when OUTPUT_ISYN_READY =>
          current_state <= OUTPUT_LIF_PROCESSING; -- Next clock cycle, the new I_syn is ready and output neurons can use it.

        when HIDDEN_LIF_PROCESSING =>
          current_state <= LOAD_OUTPUT_LAYER; -- Transition to loading the output layer after processing the hidden layer

        when OUTPUT_LIF_PROCESSING =>
          current_state <= OUTPUT_SPIKE_COUNTING; -- Transition to counting output spikes after processing the output layer 

        when OUTPUT_SPIKE_COUNTING =>

          if timestep_counter < T - 1 then
            timestep_counter <= timestep_counter + 1;
            current_state    <= LOAD_HIDDEN_LAYER; -- Start processing the hidden layer for the next timestep
          else
            timestep_counter <= 0; -- Reset timestep counter
            current_state    <= ARGMAX_COMPUTING; -- After processing all timesteps, transition to argmax computing.
          end if;

        when ARGMAX_COMPUTING =>
          prediction_ready <= '1'; -- Signal that a new prediction is ready.

          if sample_counter < NUM_SAMPLES - 1 then
            sample_counter <= sample_counter + 1;
            reset_counter  <= '1'; -- We have to reset the counter for the new sample.
            rst_V          <= '1'; -- We have to reset the membrane potentials for the new sample.
            current_state  <= RESET_STATE; -- Go to reset state before starting the next sample.
          else
            sample_counter <= 0; -- Reset sample counter
            current_state  <= IDLE; -- Transition back to IDLE or you can choose to stay in ARGMAX_COMPUTING if you want to keep the results for all samples.
          end if;

      end case;

    end if;

  end process;

  -- Concurrent Assignments for updating output ports based on the current counters.
  sample_idx   <= sample_counter;
  timestep_idx <= timestep_counter;
  pixel_idx    <= pixel_counter;
  neuron_idx   <= neuron_counter;

  -- By using concurrent assignments, we make sure that modules only work in their correct state.
  -------------------------------------------------------------------------------------------------
  count_spike_valid <= '1' when current_state = OUTPUT_SPIKE_COUNTING else
    '0'; -- Only count the output spike if we are at the OUTPUT_SPIKE_COUNTING state.

  en_hidden <= '1' when current_state = LOAD_HIDDEN_LAYER else
    '0'; -- Only enable the hidden synapse accumulators if we are at the LOAD_HIDDEN_LAYER state.

  en_output <= '1' when current_state = LOAD_OUTPUT_LAYER else
    '0'; -- Only enable the output synapse accumulators if we are at the LOAD_OUTPUT_LAYER state.

  prep_Isyn_hidden <= '1' when current_state = HIDDEN_ISYN_READY else
    '0'; -- Only prepare the final I_syn value for the hidden neurons if we are at the HIDDEN_LIF_PROCESSING state.

  en_lif_hidden <= '1' when current_state = HIDDEN_LIF_PROCESSING else
    '0'; -- Only enable the hidden LIF neurons if we are at the HIDDEN_LIF_PROCESSING state.

  prep_Isyn_output <= '1' when current_state = OUTPUT_ISYN_READY else
    '0'; -- Only prepare the final I_syn value for the output neurons if we are at the OUTPUT_LIF_PROCESSING state.

  en_lif_output <= '1' when current_state = OUTPUT_LIF_PROCESSING else
    '0'; -- Only enable the output LIF neurons if we are at the OUTPUT_LIF_PROCESSING state.

  calculate_argmax <= '1' when current_state = ARGMAX_COMPUTING else
    '0'; -- Only calculate the argmax if we are at the ARGMAX_COMPUTING state.

end Behavioral;