-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): xlitvi02 <login AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

-- PTR (pointer to data memory)
signal ptr : std_logic_vector(12 downto 0);
signal ptr_inc : std_logic;
signal ptr_dec : std_logic;

-- PC (program counter)
signal pc : std_logic_vector(12 downto 0);
signal pc_inc : std_logic;
signal pc_dec : std_logic;

-- CNT (counter for loops)
signal cnt : std_logic_vector(7 downto 0);
signal cnt_inc : std_logic;
signal cnt_dec : std_logic;
signal cnt_load : std_logic;
signal cnt_reset : std_logic;

-- Signals for help
signal mx_data : std_logic;
signal mx_input : std_logic_vector(1 downto 0);

-- FSM (finite state machine)
type state_type is (state_reset, state_fetch, state_decode, state_halt,
                    bf_s_beforeidle, bf_s_idle, bf_s_afteridle,
                    ptr_increment_s, ptr_decrement_s,
                    value_increment_s, value_increment_s_takt2,
                    value_decrement_s, value_decrement_s_takt2,
                    print_s, print_s_takt2,
                    read_s, read_s_takt2,
                    start_while1_s, start_while2_s, start_while3_s, start_while4_s, start_while5_s,
                    end_while1_s, end_while2_s, end_while3_s, end_while4_s, end_while5_s,
                    breaking_s, breaking2_s,
                    s_null);

signal prev_state : state_type;
signal next_state : state_type;
attribute fsm_encoding : string;
attribute fsm_encoding of prev_state : signal is "sequential";
attribute fsm_encoding of next_state : signal is "sequential";

begin

  -- Program counter
  PC_reg : process(CLK, RESET, pc_inc, pc_dec)
  begin
    if(RESET = '1') then
      pc <= (others => '0');
    elsif (CLK'event) and (CLK = '1') then
      if(pc_inc ='1') then
        pc <= pc + 1;
      elsif(pc_dec ='1') then
        pc <= pc - 1;
      end if;
    end if;
  end process;

  -- CNT register
  CNT_reg : process(CLK, RESET, cnt_inc, cnt_dec)
  begin
    if(RESET = '1') then
      cnt <= (others => '0');
    elsif (CLK'event) and (CLK = '1') then
      if (cnt_load = '1') then
        cnt <= X"01";
      elsif(cnt_inc = '1') then
        cnt <= cnt + 1;
      elsif(cnt_dec = '1') then
        cnt <= cnt - 1;
      end if;
    end if;
  end process;

  -- cnt_reset (checking if the cnt is in state 0)
  CNT_reset_pr : process(CNT)
  begin
    if(CNT = X"00") then
      cnt_reset <= '1';
    else
      cnt_reset <= '0';
    end if;
  end process; 

  -- PTR register
  PTR_reg : process(CLK, RESET, ptr_inc, ptr_dec)
  begin
    if(RESET = '1') then
      ptr <= (others => '0');
    elsif (CLK'event) and (CLK = '1') then
      if(ptr_inc = '1') then
        ptr <= ptr + 1;
      elsif(ptr_dec = '1') then 
        ptr <= ptr - 1;
      end if;
    end if;
  end process;
  
  -- MUX (send data to RAM)
  MX_RDATA : process(pc, ptr, mx_data)
  begin
    case mx_data is
      when '0' => DATA_ADDR <= ptr;
      when '1' =>DATA_ADDR <= pc;
      when others => null;
    end case;
  end process;
  
  -- MUX (send data to wdata)
  MX_INDATA : process(mx_input, IN_DATA, DATA_RDATA)
  begin
    case mx_input is
      when "00"   => DATA_WDATA <= IN_DATA;
      when "01"   => DATA_WDATA <= DATA_RDATA - 1;
      when "10"   => DATA_WDATA <= DATA_RDATA + 1;
      when "11"   => DATA_WDATA <= DATA_RDATA;
      when others => null;
    end case;
  end process;

  -- PSreg (present state register)
  PS_reg : process(CLK, RESET)
  begin
    if(RESET='1') then
      prev_state <= state_reset;
    elsif(CLK'event and CLK='1' and EN='1') then
      prev_state <= next_state;
    end if;
  end process;


  -- FSM (final logic for state machine)
  logic_nstate : process(IN_VLD, OUT_BUSY, DATA_RDATA, cnt, EN, prev_state)
  begin
    OUT_DATA <= (others => '0');
    DATA_RDWR <= '0';
    DATA_EN <= '0';
    OUT_WE <= '0';
    IN_REQ <= '0';
    ptr_inc <= '0';
    ptr_dec <= '0';
    pc_inc <= '0';
    pc_dec <= '0';
    cnt_inc <= '0';
    cnt_dec <= '0';
    cnt_load <= '0';
    mx_data <= '0';
    mx_input <= "00";
    ready <= '0';
    done <= '0';

    case prev_state is
      -- STATE_HALT (cycle for ending the program)
      when state_halt =>
        ready <= '1';
        done <= '1';
        next_state <= state_halt;

      -- STATE_RESET (reseting the status)
      when state_reset =>
        next_state <= bf_s_beforeidle;
        ready <= '0';
        done <= '0';

      -- BF_S_BEFOREIDLE (cycle before idle)
      when bf_s_beforeidle =>
        DATA_EN <= '1';
        next_state <= bf_s_idle;

      -- BF_S_IDLE (idle cycle)
      when bf_s_idle =>
        if(DATA_RDATA = X"40") then
          DATA_EN <= '0';
          next_state <= bf_s_afteridle;
        else
          DATA_EN <= '1';
          ptr_inc <= '1';
          next_state <= bf_s_idle;
        end if;
      when bf_s_afteridle =>
        ready <= '1';
        mx_data <= '1';
        next_state <= state_fetch;

      -- STATE_FETCH (read next instruction from memory)
      when state_fetch =>
        mx_data <= '1';
        DATA_EN <= '1';
        ready <= '1';
        next_state <= state_decode;

      -- STATE_DECODE (decode BrnFck instruction)
      when state_decode =>
        DATA_EN <= '1';
        case(DATA_RDATA) is
          when X"3E" => next_state <= ptr_increment_s;
          when X"3C" => next_state <= ptr_decrement_s;
          when X"2B" => next_state <= value_increment_s;
          when X"2D" => next_state <= value_decrement_s;
          when X"5B" => next_state <= start_while1_s;
          when X"5D" => next_state <= end_while1_s;
          when X"7E" => next_state <= breaking_s;
          when X"2E" => next_state <= print_s;
          when X"2C" => next_state <= read_s;
          when X"40" => next_state <= state_halt;
          when others => 
            pc_inc <= '1';
            next_state <= state_fetch;
        end case;

       ------------------POINTER------------------

        -- PTR_INCREMENT_S (increment pointer)
        when ptr_increment_s =>
          ptr_inc <= '1';
          pc_inc <= '1';
          next_state <= state_fetch;

        -- PTR_DECREMENT_S (decrement pointer)
        when ptr_decrement_s =>
          ptr_dec <= '1';
          pc_inc <= '1';
          next_state <= state_fetch;

      -------------------VALUE--------------------

        -- VALUE_INCREMENT_S (increment value)
        when value_increment_s =>
          mx_data <= '0';
          DATA_RDWR <= '0';
          DATA_EN <= '1';

          next_state <= value_increment_s_takt2;

        -- VALUE_INCREMENT_S_TAKT2 (increment value)
        when value_increment_s_takt2 =>
          mx_data <= '0';
          mx_input <= "10";
          DATA_RDWR <= '1';
          DATA_EN <= '1';

          pc_inc <= '1';
          next_state <= state_fetch;
        
        
        -- VALUE_DECREMENT_S (decrement value)
        when value_decrement_s =>
          mx_data <= '0';
          DATA_RDWR <= '0';
          DATA_EN <= '1';

          next_state <= value_decrement_s_takt2;

        -- VALUE_DECREMENT_S_TAKT2 (decrement value)
        when value_decrement_s_takt2 =>
          mx_data <= '0';
          mx_input <= "01";
          DATA_RDWR <= '1';
          DATA_EN <= '1';

          pc_inc <= '1';
          next_state <= state_fetch;

      -------------------PRINT--------------------

        -- PRINT_S (print value)
        when print_s =>
          mx_data <= '0';
          DATA_EN <= '1';

          if(OUT_BUSY = '0') then
            next_state <= print_s_takt2;
          else
            next_state <= print_s;
          end if;

        -- PRINT_S_TAKT2 (print value)
        when print_s_takt2 =>
          OUT_DATA <= DATA_RDATA;
          OUT_WE <= '1';

          pc_inc <= '1';
          next_state <= state_fetch;

      -------------------READ--------------------

        -- READ_S (read value)
        when read_s =>
          IN_REQ <= '1';

          if(IN_VLD = '1') then
            next_state <= read_s_takt2;
          else
            next_state <= read_s;
          end if;

        -- READ_S_TAKT2 (read value)
        when read_s_takt2 =>
          pc_inc <= '1';
          mx_data <= '0';
          mx_input <= "00";
          DATA_RDWR <= '1';
          DATA_EN <= '1';

          next_state <= state_fetch;

      -------------------WHILE--------------------

        -- START_WHILE1_S (start while)
        when start_while1_s =>
          mx_data <= '0';
          DATA_EN <= '1';
          DATA_RDWR <= '0';

          pc_inc <= '1';
          next_state <= start_while2_s;

        -- START_WHILE2_S (start while)
        when start_while2_s =>
          if(DATA_RDATA = X"00") then
            cnt_load <= '1';
            mx_data <= '1';
            DATA_RDWR <= '1';
            DATA_EN <= '1';

            next_state <= start_while3_s;
          else
            next_state <= state_fetch;
          end if;
        
        -- START_WHILE3_S (start while)
        when start_while3_s =>
          mx_data <= '1';
          DATA_RDWR <= '0';
          DATA_EN <= '1';

          pc_inc <= '1';
          next_state <= start_while4_s;

        -- START_WHILE4_S (start while)
        when start_while4_s =>
          DATA_EN <= '1';
          if(DATA_RDATA = X"5B") then
            cnt_inc <= '1';
          elsif (DATA_RDATA = X"5D") then
            cnt_dec <= '1';
          end if;
          next_state <= start_while5_s;

        -- START_WHILE5_S (start while)
        when start_while5_s =>
          pc_inc <= '1';
          if(cnt_reset = '1') then
            done <= '1';
            next_state <= state_fetch;
          else
            next_state <= start_while3_s;
          end if;


        -- END_WHILE1_S (end while)
        when end_while1_s =>
          mx_data <= '0';
          DATA_RDWR <= '0';
          DATA_EN <= '1';

          next_state <= end_while2_s;

        -- END_WHILE2_S (end while)
        when end_while2_s =>
          if(DATA_RDATA = X"00") then
            pc_inc <= '1';
            next_state <= state_fetch;
          else
            ready <= '1';
            cnt_load <= '1';
            pc_dec <= '1';
            DATA_EN <= '1';

            next_state <= end_while3_s;
          end if;

        -- END_WHILE3_S (end while)
        when end_while3_s =>
          mx_data <= '1';
          DATA_RDWR <= '0';
          DATA_EN <= '1';

          next_state <= end_while4_s;

        -- END_WHILE4_S (end while)
        when end_while4_s =>
          ready <= '1';
          DATA_EN <= '1';
          if(DATA_RDATA = X"5D") then
            cnt_inc <= '1';
          elsif (DATA_RDATA = X"5B") then
            cnt_dec <= '1';
          end if;
          next_state <= end_while5_s;

        -- END_WHILE5_S (end while)
        when end_while5_s =>
          if(cnt_reset = '1') then
            pc_inc <= '1';
            next_state <= state_fetch;
          else
            ready <= '1';
            DATA_EN <= '1';
            pc_dec <= '1';

            next_state <= end_while3_s;
          end if;

      -------------------BREAK--------------------

        -- BREAKING_S (breaking while)
        when breaking_s =>
          mx_data <= '1';
          DATA_EN <= '1';

          next_state <= breaking2_s;

        -- BREAKING2_S (breaking while)
        when breaking2_s =>
          DATA_EN <= '1';
          mx_data <= '1';
          if(DATA_RDATA = X"5D") then
            pc_inc <= '1';
            cnt_dec <= '1';

            next_state <= state_fetch;
          elsif(DATA_RDATA = X"5B") then
            next_state <= state_halt;
          else
            pc_inc <= '1';
            next_state <= breaking_s;
          end if;

        when others => next_state <= state_reset;
    
    end case;
  end process;


end behavioral;

