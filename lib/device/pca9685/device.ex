defmodule DevcontrolI2c.PCA9685.Device do
  @moduledoc """
  PCA9685 Chip Device functions
  """
  require Logger

  # device configuration
  @externalclk 0b0      # external: 1, innerclk: 0
  @innerclock 25_000_000  #Hz source clock
  @clock @innerclock
  @refresh_freq 50        # Hz making pulse freq 50Hz-20ms
  @prescale round(@clock/(4096 * 50) - 1)
  @ms1_pls round(4096/(@refresh_freq/1000))  # 1ms pulse width in 12bit counter for servo
  @shift_pls 200        # in 20[ms] case, about 1.0ms
  
  @autoincrement 0b1  # This module is under ai mode, so don't change
  @useofsubadd 0b000  # This module is Not supported 
  # mode 2 setting 
  @inverted 0b0       # Output logic stgate inverted(1) or not(0)
  @outchange 0b0      # Output change on STOP command(0) or on ACK(1)
  @outdrive 0b1       # open-drain: 0, totem pole: 1
  @outnegate 0b00     # 

  # bit strucuture [name: bits,...] 
  @st_mode1 [restart: 1, exclk: 1, ai: 1, sleep: 1, sub: 3, allcall: 1]
  @st_mode2 [rev: 3, invrt: 1, och: 1, outdrv: 1, outne: 2]
  @st_subadd [address: 7, reserved: 1]
  @st_allcall [address: 7, reserved: 1]
  @st_led [on_low: 8,on_res: 3,on_high: 5,off_low: 8,off_res: 3,off_high: 5] 
  @st_prescale [prescale: 8] 

  @d_mode1_sleep [restart: 0,
                  exclk: @externalclk,
                  ai: @autoincrement,
                  sleep: 1,
                  sub: @useofsubadd,
                  allcall: 0]
  @d_mode2 [rev: 0b000,
            invrt: @inverted,
            och: @outchange,
            outdrv: @outdrive,
            outne: @outnegate]

  @reg_map %{
      regmode1:    {   0, 1, @st_mode1,  "mode_1"},
      regmode2:    {   1, 1, @st_mode2,  "mode_2"},
      regsub1:     {   2, 1, @st_subadd, "subadd1"},
      regsub2:     {   3, 1, @st_subadd, "subadd2"},
      regsub3:     {   4, 1, @st_subadd, "subadd3"},
      regallcall:  {   5, 1, @st_allcall,"allcall"},
      regled_all:  { 250, 4, @st_led,    "led_all"},
      regprescale: {0xfe, 1, @st_prescale,  "prescale"},
      regtestmode: {0xff, 1, [testmode: 8], "testmode"},
    }

  def mode1_sleep(), do: @d_mode1_sleep
  def mode1_restart(), do: @d_mode1_sleep |> Keyword.replace( :restart, 1) |> Keyword.replace( :sleep, 0)
  def mode2_data(), do: @d_mode2
  def prescale_data(), do: @prescale

  # define guard for bus type
  defguard is_channel(ch_no) when is_integer(ch_no) and 0 <= ch_no and ch_no < 16
  # led out data includes `full bit`, then <= 4096 (0x1000)
  defguard is_1000(p_cnt) when is_integer(p_cnt) and 0 <= p_cnt and p_cnt <= 0x1000
  defguard is_freq(freq) when is_integer(freq) and 24 <= freq and freq < 1526

  @spec set_reg(atom(), keyword()) :: bitstring()
  def set_reg(regname, datpat) do
      {regno, _num, format, _msg} = get_reginfo(regname)
      values = Keyword.values(datpat)
      format = Keyword.values(format)
      w_dt = make_reg(values, format)   # values into format 
      <<regno::8, w_dt::binary>>
  end

  @doc """
    set ontime and off time pulse counter into register format 
    then append <<onreg>> <> <<offreg>>   

    #example 
    iex> set_ledpat(0, 4095)
    <<0::16, 0xff0f::16>>
    iex>set_ledpat(4095, 0)
    <<0xff0f::16, 0::16>>
    iex>set_ledpat(2047, 2047)
    <<0xff07::16, 0xff07::16>>

  """
  @spec set_ledpat(integer(), integer()) :: bitstring()   # <<ontime::16, offtime::16>>
  def set_ledpat(ontime, offtime) when is_1000(ontime) and is_1000(offtime) do
    <<_::3, high::5, low::8>> = <<ontime::16>>
    on_bin = <<low::8, 0::3, high::5>> 
    <<_::3, high::5, low::8>> = <<offtime::16>>
    off_bin = <<low::8, 0::3, high::5>> 
    on_bin <> off_bin
  end
  
  @doc """
  get prescale how many times(division) by source-cycle to make refresh cycle (e.g. 50Hz=20ms) 
      
  """
  #@spec get_prescale() :: binary()
  #def get_prescale() do
  #  @default_prescale
  #end
  #@spec get_prescale(integer(), integer()) :: binary()
  #def get_prescale(clock, cycle) when is_freq(cycle) do
  #  round(clock/(4096 * cycle) - 1)
  #end

  #def get_1msbits() do
  #  width = 1000/@refresh_freq    # 20(ms) cycle time[ms] 1000[ms]/freq(50Hz)
  #  round(4096/width)     # 4096/cycle time(20[ms]) 
  #end

  @spec make_reg(list(), list()) :: bitstring()
  def make_reg(values, format) when length(values) == length(format) do
    Enum.zip(values, format)
    |> Enum.reduce(<<>>,
              fn {val, size}, acc -> 
                <<acc::bitstring, val::size(size)>>
              end)
  end

  @doc """
  integer data casts to <<key1::size1, ....>> -> [key1: data1, ...]
        
    iex> parse(0x55, [a: 2, b: 3, c: 2, d: 1])
    [a: 1, b: 2, c: 2, d: 1]
    iex> parse(0xaa, [a: 2, b: 3, c: 2, d: 1])
    [a: 2, b: 5, c: 1, d: 0]

  """
  @spec parse(binary(), keyword()) :: keyword()
  def parse(data, format) when is_binary(data) do
    do_parse(data, format, [])
  end
    # until format exists, set bits into format, then reverse
    defp do_parse(_rest, [], acc), do: Enum.reverse(acc)
    defp do_parse(rest, [{key, size} | tail], acc) do
      <<value::size(size), remaining::bitstring>> = rest
      do_parse(remaining, tail, [{key, value} | acc])
    end

  @doc """
  binary 16 bits data casts to {ontime, offtime} 
    
  iex> parse_led(<<0x55, 0x0a, 0xaa, 0x05>>) 
    {0xa55, 0x5aa}
  iex> parse_led(<<0xaa, 0x05, 0x55, 0x0a>>) 
    {0x5aa, 0xa55}

  """
  @spec parse_led(binary()) :: {integer(), integer()}  # {ontime, offtime}
  def parse_led(bin) when is_bitstring(bin) do
    <<on_low::8, _::3, on_high::5, off_low::8, _::3, off_high::5>> = bin
    <<ontime::16, offtime::16>> = <<0::3, on_high::5, on_low::8, 0::3, off_high::5, off_low::8>>
    {ontime, offtime}
  end

  @spec get_regallinfo() :: none()
  def get_regallinfo() do
    keys = Map.keys(@reg_map)
    Enum.each(keys, fn key -> 
      {regno, num, _format, msg} = Map.get(@reg_map, key)
      IO.puts("#{key} #{regno}-#{num} \"#{msg}\"")
    end) 
  end

  @spec get_reginfo(atom()) :: {integer(), integer(), list(), String.t()}
  def get_reginfo(reg_name) do
    {regno, num, format, msg} = Map.get(@reg_map, reg_name)
  end

  def difference(a, []), do: a
  def difference([], _b), do: []
  def difference(a, b) when is_list(a) and is_list(b) do
    a 
    |> MapSet.new( ) 
    |> MapSet.difference( MapSet.new(b)) 
    |> MapSet.to_list( ) 
  end
  
  @doc """
  offtime - ontime = rangepulse 1.0ms
   0%    - 100%
   1.0ms - 2.0ms

  iex> percto_servo(1, 0)
  {200, 405}
  iex> percto_servo(2, 100)
  {400, 810}
  iex> percto_servo(3, 50)
  {600, 907}
  """
  @spec percto_servo(ch_no :: integer(), percentage :: integer()) :: {integer(), integer()}
  def percto_servo(ch_no, percentage) when percentage <= 0 do
    ontime = ch_no * @shift_pls     # shift time to avoid simalteneous output
    offtime = ontime + round(@ms1_pls)
    {ontime, offtime}
  end 

  def percto_servo(ch_no, percentage) when 100 <= percentage do
    ontime = ch_no * @shift_pls     # shift time to avoid simalteneous output
    offtime = ontime + round(@ms1_pls) * 2
    if 4096 <= offtime do
      {ontime, offtime - 4096}
    else
      {ontime, offtime}
    end
  end
  def percto_servo(ch_no, percentage) do
    ontime = ch_no * @shift_pls     # shift time to avoid simalteneous output
    # 1.0ms-2.0ms:0-100%, pulse/1% * percentage 
    offtime = round(@ms1_pls/100 * percentage) + ontime + round(@ms1_pls)
    if 4096 <= offtime do
      {ontime, offtime - 4096}
    else
      {ontime, offtime}
    end
  end

  def percto_duty(_ch_no, percentage) when percentage <= 0, do: {0, 0x1000}    # all off
  def percto_duty(_ch_no, percentage) when 100 <= percentage, do: {0x1000, 0}  # all on
  def percto_duty(ch_no, percentage) do
    # 0% -100% -> 0 - 4095
    ontime = ch_no * @shift_pls    # shift time to avoid simalteneous output
    offtime = round(4096/100 * percentage) + ontime
    if 4096 <= offtime do
      {ontime, offtime - 4096}
    else
      {ontime, offtime}
    end
  end

end
