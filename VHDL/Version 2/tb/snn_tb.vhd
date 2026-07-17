--- Testbench for the SNN model: Generate clk, instantiate the top-level module, load the labels and compare the results ---
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use STD.TEXTIO.all;
use IEEE.STD_LOGIC_TEXTIO.all;

entity snn_tb is
  generic (
    LABELS_FILE_PATH : string := "labels.mem"
  );
end snn_tb;

architecture Simulation of snn_tb is

  constant NUM_SAMPLES              : integer := 1000;
  constant NUM_NEURONS              : integer := 64;
  constant T                        : integer := 16;
  constant THETA                    : integer := 450;
  constant LEAK_SHIFT               : integer := 6;
  constant HIDDEN_WEIGHTS_FILE_PATH : string  := "w_hidden.mem";
  constant OUTPUT_WEIGHTS_FILE_PATH : string  := "w_output.mem";
  constant INPUT_SPIKES_FILE_PATH   : string  := "spike_patterns.mem";

  signal clk              : std_logic := '0';
  signal rst              : std_logic := '0';
  signal start            : std_logic := '0'; -- Signal to start the SNN processing
  signal predicted_label  : std_logic_vector(3 downto 0) := "1010"; -- Choosing number 10 as the out-of-bound (0 - 9) uninitalized default value.
  signal prediction_ready : std_logic := '0'; -- To signal the testbench that a new sample prediction is ready to be read.

  signal correct_labels   : integer_vector(NUM_SAMPLES - 1 downto 0) := (others => 0); -- Array to hold the reference labels for all the samples
  signal predicted_labels : integer_vector(NUM_SAMPLES - 1 downto 0) := (others => 10); -- Array to hold the predicted labels for all the samples
  signal NUM_CORRECT      : integer                                  := 0;
  signal ACCURACY         : integer                                  := 0;

  constant clk_period : time := 6 ns; -- Clock period

begin

  ------------------------------------------
  --- Process to generate the clk signal ---
  ------------------------------------------
  process
  begin
    while true loop
      clk <= '0';
      wait for clk_period/2;
      clk <= '1';
      wait for clk_period/2;
    end loop;
  end process;
  ------------------------------------------------
  --- Process to read the labels from the file ---
  ------------------------------------------------
  process

    file text_file      : text; -- File variable for reading the spike patterns
    variable text_line  : line; -- Variable to hold each line read from the file
    variable hex_read   : integer; -- Read weights as 8-bit vectors (They are originly written as 2-bit hex to be read with hread)
    variable buffer_idx : integer := 0; -- Index to keep track of where we are in the memory buffer

  begin

    -- Open the labels file in read mode
    file_open(text_file, LABELS_FILE_PATH, read_mode);

    -- Loop through all the lines and numbers in the file.
    while not endfile(text_file) and buffer_idx < NUM_SAMPLES loop

      readline(text_file, text_line);
      read(text_line, hex_read);

      -- Fill the memory buffer with the reference labels.
      correct_labels(buffer_idx) <= hex_read;
      buffer_idx := buffer_idx + 1;

    end loop;
    file_close(text_file);

    wait;
  end process;
  ----------------------------------------
  --- Instantiate the top level module ---
  ----------------------------------------
  snn_top_level_inst : entity work.snn_top_level
    generic map(
      NUM_SAMPLES              => NUM_SAMPLES,
      NUM_NEURONS              => NUM_NEURONS,
      T                        => T,
      THETA                    => THETA,
      LEAK_SHIFT               => LEAK_SHIFT,
      HIDDEN_WEIGHTS_FILE_PATH => HIDDEN_WEIGHTS_FILE_PATH,
      OUTPUT_WEIGHTS_FILE_PATH => OUTPUT_WEIGHTS_FILE_PATH,
      INPUT_SPIKES_FILE_PATH   => INPUT_SPIKES_FILE_PATH
    )
    port map
    (
      clk              => clk,
      rst              => rst,
      start            => start,
      predicted_label  => predicted_label,
      prediction_ready => prediction_ready
    );
  -----------------
  --- Simulate ----
  -----------------
  process

    variable sample_id           : integer := 0;
    variable correct_predictions : integer := 0;

  begin

    rst <= '1';
    wait for 30 ns;
    rst <= '0';
    wait for 20 ns;

    -- Start the SNN simulation
    wait until rising_edge(clk);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0'; -- This signal will be checked again after processing the last sample in the spike train. Since we set it to '0' here, it will stay at IDLE state after processing all the samples.

    wait until rising_edge(clk);

    while sample_id < NUM_SAMPLES loop

      -- Wait until a new prediction is ready
      wait until rising_edge(clk) and prediction_ready = '1';

      predicted_labels(sample_id) <= to_integer(unsigned(predicted_label));
      sample_id := sample_id + 1;

    end loop;

    -- Calculate SNN model accuracy
    wait until rising_edge(clk);

    for i in 0 to NUM_SAMPLES - 1 loop
      if predicted_labels(i) = correct_labels(i) then
        correct_predictions := correct_predictions + 1;
      end if;
    end loop;

    wait until rising_edge(clk);
    num_correct <= correct_predictions;

    wait until rising_edge(clk);
    accuracy <= (correct_predictions * 10000) / NUM_SAMPLES; -- For example 9567 means: 95.67% accuracy.

    -- End of simulation
    assert false report "Simulation finished successfully! All samples processed." severity failure;
  end process;

end Simulation;