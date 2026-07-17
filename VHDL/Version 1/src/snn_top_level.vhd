--- Top level module for the SNN implementation. This module instantiates the necessary components and connects them together ---
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity snn_top_level is
  generic (
    NUM_SAMPLES              : integer := 1;
    NUM_NEURONS              : integer := 64;
    T                        : integer := 16;
    THETA                    : integer := 450;
    LEAK_SHIFT               : integer := 6;
    HIDDEN_WEIGHTS_FILE_PATH : string  := "w_hidden.mem";
    OUTPUT_WEIGHTS_FILE_PATH : string  := "w_output.mem";
    INPUT_SPIKES_FILE_PATH   : string  := "spike_patterns.mem"
  );
  port (
    clk              : in std_logic;
    rst              : in std_logic;
    start            : in std_logic; -- Signal to start the SNN processing
    predicted_label  : out std_logic_vector(3 downto 0);
    prediction_ready : out std_logic -- To signal the testbench that a new sample prediction is ready to be read.
  );
end snn_top_level;

architecture Structual of snn_top_level is
  -- ==========================================
  -- INTERNAL SIGNALS FOR CONNECTING COMPONENTS
  -- ==========================================

  -- Controller routing signals
  signal ctrl_sample_idx   : integer range 0 to NUM_SAMPLES - 1;
  signal ctrl_timestep_idx : integer range 0 to T - 1;
  signal ctrl_pixel_idx    : integer range 0 to 783;
  signal ctrl_neuron_idx   : integer range 0 to NUM_NEURONS - 1;

  signal ctrl_prep_Isyn_hidden  : std_logic;
  signal ctrl_prep_Isyn_output  : std_logic;
  signal ctrl_en_lif_hidden     : std_logic;
  signal ctrl_en_lif_output     : std_logic;
  signal ctrl_rst_V             : std_logic;
  signal ctrl_count_spike_valid : std_logic;
  signal ctrl_reset_counter     : std_logic;
  signal ctrl_calculate_argmax  : std_logic;
  signal ctrl_en_hidden         : std_logic;
  signal ctrl_en_output         : std_logic;

  -- Argmax routing signals
  signal spike_counts_array : integer_vector(0 to 9) := (others => 0); -- This array will eventually collect the outputs of the 10 output_counters.
  signal out_v_to_argmax    : integer_vector(0 to 9) := (others => 0); -- membrane potentials to argmax unit as tie-breaker
    
  -- Internal integer to catch the argmax output before it hits the chip boundary
  signal internal_predicted_label : integer range 0 to 10 := 10;
  
  -- Output counters and output LIF neurons routing signals
  signal output_neurons_spikes : std_logic_vector(9 downto 0) := (others => '0'); -- Each bit corresponds to the output spike of one of the 10 output LIF neurons, which will be connected to the input_spike of the corresponding output_counter.

  -- Synapse accumulators and neurons routing signals
  -- 2D structure: Array of 16-bit vectors to connect 10 accumulators to 10 neurons
  type output_Isyn_array is array (0 to 9) of std_logic_vector(31 downto 0);
  signal output_Isyn : output_Isyn_array;
  -- 2D structure: Array of 16-bit vectors to connect NUM_NEURONS(64) accumulators to NUM_NEURONS(64) neurons
  type hidden_Isyn_array is array (0 to NUM_NEURONS - 1) of std_logic_vector(31 downto 0);
  signal hidden_Isyn : hidden_Isyn_array;

  -- Hidden layer LIF neurons and output synapse accumulators routing signals
  signal output_accumulators_input_spikes : std_logic_vector(9 downto 0)               := (others => '0');
  signal hidden_neurons_output_spikes     : std_logic_vector(NUM_NEURONS - 1 downto 0) := (others => '0');

  -- Input spike driver & hidden synaptic accumulators routing signals
  signal input_spike_to_hidden_accumulators : std_logic := '0';

begin

  -- ========================
  -- COMPONENT INSTANTIATIONS
  -- ========================

  -- Layer_controller --
  layer_controller_inst : entity work.layer_controller
    generic map(
      NUM_SAMPLES => NUM_SAMPLES,
      T           => T,
      NUM_NEURONS => NUM_NEURONS
    )
    port map
    (
      clk   => clk,
      rst   => rst,
      start => start,

      sample_idx   => ctrl_sample_idx,
      timestep_idx => ctrl_timestep_idx,
      pixel_idx    => ctrl_pixel_idx,
      neuron_idx   => ctrl_neuron_idx,

      prep_Isyn_hidden  => ctrl_prep_Isyn_hidden,
      prep_Isyn_output  => ctrl_prep_Isyn_output,
      en_lif_hidden     => ctrl_en_lif_hidden,
      en_lif_output     => ctrl_en_lif_output,
      rst_V             => ctrl_rst_V,
      en_hidden         => ctrl_en_hidden,
      en_output         => ctrl_en_output,
      count_spike_valid => ctrl_count_spike_valid,
      reset_counter     => ctrl_reset_counter,
      calculate_argmax  => ctrl_calculate_argmax,
      prediction_ready  => prediction_ready -- Routes directly to the top-level output.
    );

  -- argmax_ubit --
  argmax_unit_inst : entity work.argmax_unit
    port map
    (
      clk                   => clk,
      rst                   => rst,
      spike_counts          => spike_counts_array,
      predicted_label       => internal_predicted_label, -- Routes directly to the top-level output.
      calculate_argmax      => ctrl_calculate_argmax,
      v_from_output_neurons => out_v_to_argmax -- membrane potentials to argmax unit as tie-breaker
    );

  -- 10 output_counters --
  gen_output_counters : for i in 0 to 9 generate
    output_counter_inst : entity work.output_counter
      generic map(
        T => T
      )
      port map
      (
        clk               => clk,
        rst               => rst,
        input_spike       => output_neurons_spikes(i), -- Connect the input spike of the i-th output_counter to the output_spike of the i-th output LIF neuron.
        input_spike_valid => ctrl_count_spike_valid,
        reset_counter     => ctrl_reset_counter,
        spike_count       => spike_counts_array(i) -- Connect each output counter's spike count to the corresponding index in the spike_counts_array.
      );
  end generate;

  -- 10 output LIF neurons --
  gen_output_lif_neurons : for i in 0 to 9 generate
    lif_neuron_inst : entity work.lif_neuron
      generic map(
        theta      => THETA,
        leak_shift => LEAK_SHIFT
      )
      port map
      (
        clk          => clk,
        rst          => rst,
        I_syn        => output_Isyn(i), -- Connect the I_syn input of the i-th output LIF neuron to the output of the i-th synapse accumulator.
        en_lif       => ctrl_en_lif_output, -- Connect to the controller's en_lif_output signal.
        rst_V        => ctrl_rst_V,
        output_spike => output_neurons_spikes(i), -- Connect the output spike of the i-th output LIF neuron to the input_spike of the i-th output_counter.
        V_out        => out_v_to_argmax(i) -- membrane potentials to argmax unit as tie-breaker
      );
  end generate;

  ------------------------------------------------------------------------------
  --- Connecting hidden layer LIF neurons to the output synapse accumulators ---
  ------------------------------------------------------------------------------

  -- At each clock cycle, each hidden neuron gives it's value ('0' or '1') to all the output synapse accumulators. The hidden neuron's index is controlled by the layer_controller
  output_accumulators_input_spikes <= (others => hidden_neurons_output_spikes(ctrl_neuron_idx)); -- This can act as a wire conncetion and is updated at each clock cycle by ctrl_neuron_idx.

  -- 10 output synaptic accumulators --
  gen_output_synapse_accumulators : for i in 0 to 9 generate
    synapse_accumulator_inst : entity work.synapse_accumulator
      generic map(
        weight_array_size => NUM_NEURONS, -- Each output neuron has 64 synapses coming from the 64 hidden neurons.
        neuron_idx        => i,
        weight_file_path  => OUTPUT_WEIGHTS_FILE_PATH
      )
      port map
      (
        clk         => clk,
        rst         => rst,
        input_spike => output_accumulators_input_spikes(i),
        accum_en    => ctrl_en_output, -- Connect to the controller's en_output signal.
        prep_Isyn   => ctrl_prep_Isyn_output, -- Connect to the controller's prep_Isyn_output signal.
        I_syn       => output_Isyn(i) -- Connect the output I_syn of the i-th synapse accumulator to the I_syn input of the i-th output LIF neuron.
      );
  end generate;

  -- NUM_NEURONS (64) hidden LIF neurons --
  gen_hidden_lif_neurons : for i in 0 to NUM_NEURONS - 1 generate
    lif_neuron_inst : entity work.lif_neuron
      generic map(
        theta      => THETA,
        leak_shift => LEAK_SHIFT
      )
      port map
      (
        clk          => clk,
        rst          => rst,
        I_syn        => hidden_Isyn(i), -- Connect to the output of the hidden layer synapse accumulators later.
        en_lif       => ctrl_en_lif_hidden, -- Connect to the controller's en_lif_hidden signal.
        rst_V        => ctrl_rst_V,
        output_spike => hidden_neurons_output_spikes(i),
        V_out        => open
      );
  end generate;

  -------------------------------------------------------------------------
  --- Connecting input spike driver to the hidden synaptic accumulators ---
  -------------------------------------------------------------------------

  -- NUM_NEURONS (64) hidden synaptic accumulators --
  gen_hidden_synapse_accumulators : for i in 0 to NUM_NEURONS - 1 generate
    synapse_accumulator_inst : entity work.synapse_accumulator
      generic map(
        weight_array_size => 784, -- Each hidden neuron has 784 synapses coming from the 784 input pixels.
        neuron_idx        => i,
        weight_file_path  => HIDDEN_WEIGHTS_FILE_PATH
      )
      port map
      (
        clk         => clk,
        rst         => rst,
        input_spike => input_spike_to_hidden_accumulators,
        accum_en    => ctrl_en_hidden, -- Connect to the controller's en_hidden signal.
        prep_Isyn   => ctrl_prep_Isyn_hidden, -- Connect to the controller's prep_Isyn_hidden signal.
        I_syn       => hidden_Isyn(i) -- Connect the output synaptic current of the i-th hidden synapse accumulator to the input of the i-th hidden LIF neuron.
      );
  end generate;

  -- Input spike driver --
  input_spike_driver_inst : entity work.input_spike_driver
    generic map(
      input_spikes_file_path => INPUT_SPIKES_FILE_PATH,
      NUM_SAMPLES            => NUM_SAMPLES,
      T                      => T
    )
    port map
    (
      clk          => clk,
      rst          => rst,
      sample_idx   => ctrl_sample_idx,
      timestep_idx => ctrl_timestep_idx,
      pixel_idx    => ctrl_pixel_idx,
      spike_out    => input_spike_to_hidden_accumulators
    );

  -- Converts the internal integer prediction to the external 4-bit hardware bus
  predicted_label <= std_logic_vector(to_unsigned(internal_predicted_label, 4));
  
end Structual;