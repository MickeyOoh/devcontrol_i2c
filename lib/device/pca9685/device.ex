defmodule DevcontrolI2c.PCA9685.Device do
  @moduledoc """
  PCA9685 Chip Device functions
  """
  require Logger

	@type percent() :: non_neg_integer()	# 0-100%
	@type counter() :: non_neg_integer()	# 0-4095, 4096 pulses
	@type led_no() :: non_neg_integer()	# 0-15 led_no

  # device configuration
  @externalclk 0b0      # external: 1, innerclk: 0
    @innerclock 25_000_000  #Hz source clock
    @clock @innerclock
    @refresh_freq 50        # Hz making pulse freq 50Hz-20ms
    @prescale round(@clock/(4096 * @refresh_freq) - 1)
    @ms1_pls round(4096/(1000/@refresh_freq))  # 1ms pulse width in 12bit counter for servo
    @shift_pls 200        # in 20[ms] case, about 1.0ms for shift on timing
  
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
  @st_led [on_low: 8, on_res: 3, on_high: 5, off_low: 8, off_res: 3, off_high: 5] 
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
  
  def mode1_sleep(), do: @d_mode1_sleep
  def mode1_restart(), do: @d_mode1_sleep |> Keyword.replace( :restart, 1) |> Keyword.replace( :sleep, 0)
  def mode2_data(), do: @d_mode2
  def d_sysinfo(), do: [clock: @clock, cycle: @refresh_freq, mode1: @d_mode1_sleep, mode2: @d_mode2, prescale: @prescale]
  def prescale_data(), do: @prescale

  # define guard for bus type
  #defguard is_ledn(ledn) when is_integer(ledn) and 0 <= ledn and ledn < 16
  # led out data includes `full bit`, then <= 4096 (0x1000)
  #defguard is_1000(p_cnt) when is_integer(p_cnt) and 0 <= p_cnt and p_cnt <= 0x1000
  #defguard is_freq(freq) when is_integer(freq) and 24 <= freq and freq < 1526

  @doc """
  set register data into register format
  
  # example
  iex> set_reg(:regmode1, [restart: 0,exclk: 0,ai: 1,sleep: 1,sub: 0,allcall: 0])
  <<0, 48>>

  iex> set_reg(:regmode2, [rev: 0, invrt: 1, och: 0, outdrv: 1, outne: 1])
  <<1, 21>>

  """
  @spec set_reg(atom(), keyword()) :: bitstring()
  def set_reg(regname, datpat) do
      {regno, _num, format, _msg} = get_reginfo(regname)
      values = Keyword.values(datpat)
      format = Keyword.values(format)
      w_dt = make_reg(values, format)   # values into format 
      <<regno::8, w_dt::binary>>
  end

  @doc """
  set values into format(bitstructure)
  example values - [a: 1, b: 2, c: 3, d: 0] -> [1, 2, 3, 0]
          format - [a: 2, b: 3, c: 2, d: 1] -> [2, 3, 2, 1]
          << 1::size(2), 2::size(3), 3::size(2), 0::size(1)>> -> 0b01010110 -> 0x56 -> 86d
  # example
  
    iex> make_reg([1, 2, 3, 0], [2, 3, 2, 1]) 
    <<86>>
    
  """
  @spec make_reg(list(), list()) :: bitstring()
  def make_reg(values, format) when length(values) == length(format) do
    Enum.zip(values, format)
    |> Enum.reduce(<<>>,
              fn {val, size}, acc -> 
                <<acc::bitstring, val::size(size)>>
              end)
  end

  @doc """
    set ontime and off time pulse counter into register format 
    then append <<onreg>> <> <<offreg>> 
    if ontime and offtime are out of range, they will be clipped. 
    when they are the same counter, offtime is set full-off(0x1000)
    #example 
    iex> set_ledpat(0, 4095)
    <<0, 0, 255, 15>>
    iex>set_ledpat(4095, 0)
    <<255, 15, 0, 0>>
    iex>set_ledpat(2047, 2046)
    <<255, 7, 254, 7>>
    iex>set_ledpat(2047, 2047)
    <<0, 0, 0, 16>>

  """
  @spec set_ledpat(ontime :: counter(), offtime :: counter()) :: bitstring()   # 32bits 
  def set_ledpat(ontime, offtime) when ontime == offtime, do: set_ledpat(0, 0x1000) 
  def set_ledpat(ontime, offtime) when offtime < 0, do: set_ledpat(ontime, 0) 
  def set_ledpat(ontime, offtime) when ontime  < 0, do: set_ledpat(0, offtime) 
  def set_ledpat(_ontime, offtime) when 0x1000 < offtime, do: set_ledpat(0, 0x1000) 
  def set_ledpat(ontime, _offtime) when 0x1000 < ontime,  do: set_ledpat(0x1000, 0) 
  def set_ledpat(ontime, offtime) do
    <<_::3, high::5, low::8>> = <<ontime::16>>
    on_bit16 = <<low::8, 0::3, high::5>> 
    <<_::3, high::5, low::8>> = <<offtime::16>>
    off_bit16 = <<low::8, 0::3, high::5>> 
    on_bit16 <> off_bit16
  end

  @doc """
  integer data casts to <<key1::size1, ....>> -> [key1: data1, ...]

  ## Examples
  
    iex> parse(<<0x55>>, [a: 2, b: 3, c: 2, d: 1])
    [a: 1, b: 2, c: 2, d: 1]
    iex> parse(<<0xaa>>, [a: 2, b: 3, c: 2, d: 1])
    [a: 2, b: 5, c: 1, d: 0]

  """
  @spec parse(bitstring(), keyword()) :: keyword()
  def parse(data, format) when is_bitstring(data) do
    do_parse(data, format, [])
  end
    # until format exists, set bits into format, then reverse
    defp do_parse(_rest, [], acc), do: Enum.reverse(acc)
    defp do_parse(rest, [{key, size} | tail], acc) do
      <<value::size(size), remaining::bitstring>> = rest
      do_parse(remaining, tail, [{key, value} | acc])
    end

  @doc """
  transform regsiter to counter ( 0 - 4096)
  binary 16 + 16 bits data casts to {ontime, offtime} 

  # Example

    iex> parse_led(<<0x55, 0x0a, 0xaa, 0x05>>) 
    {2645, 1450}

    iex> parse_led(<<0xaa, 0x05, 0x55, 0x0a>>) 
    {1450, 2645}

  """
  @spec parse_led(bitstring()) :: {counter(), counter()}  # {ontime, offtime}
  def parse_led(bit32) when is_bitstring(bit32) do
    <<on_low::8, _::3, on_high::5, off_low::8, _::3, off_high::5>> = bit32
    <<ontime::16, offtime::16>> = <<0::3, on_high::5, on_low::8, 0::3, off_high::5, off_low::8>>
    {ontime, offtime}
  end

  @doc """
    calculate prescale
      clock/(4096 * cycle) - 1 
    # Example 
      
      iex> get_prescale(25_000_000, 200)
      30
      iex> get_prescale(25_000_000, 23)
      253
      iex> get_prescale(25_000_000, 1526)
      3

  """
  @spec get_prescale(clock :: integer(), cycle :: integer()) :: binary()
  def get_prescale(clock, cycle) when cycle < 24, do: get_prescale(clock, 24)
  def get_prescale(clock, cycle) when 1526 <= cycle, do: get_prescale(clock, 1525)
  def get_prescale(clock, cycle) do
    round(clock/(4096 * cycle) - 1)
  end

  @reg_map %{
      regmode1:    {   0, 1, @st_mode1,  "mode_1"},
      regmode2:    {   1, 1, @st_mode2,  "mode_2"},
      regsub1:     {   2, 1, @st_subadd, "subadd1"},
      regsub2:     {   3, 1, @st_subadd, "subadd2"},
      regsub3:     {   4, 1, @st_subadd, "subadd3"},
      regallcall:  {   5, 1, @st_allcall, "allcall"},
      regled_all:  { 250, 4, @st_led,    "led_all"},
      regprescale: {0xfe, 1, @st_prescale,  "prescale"},
      regtestmode: {0xff, 1, [testmode: 8], "testmode"},
    }

  @doc """
    all information of register definition 

  """
  @spec get_regallinfo(none() | :values | :keys | any()) :: map() | list()
  def get_regallinfo(), do: @reg_map
  def get_regallinfo(:values), do: Map.values(@reg_map)
  def get_regallinfo(_kind), do: Map.keys(@reg_map)

  @spec get_reginfo(atom()) :: {integer(), integer(), list(), String.t()}
  def get_reginfo(reg_name) do
    result = Map.get(@reg_map, reg_name)
    case result do
      {regno, num, format, msg} -> 
              {regno, num, format, msg}
      _ -> 
          raise ArgumentError, "Invalid register name: #{reg_name}"
    end
  end

  #def difference(a, []), do: a
  #def difference([], _b), do: []
  #def difference(a, b) when is_list(a) and is_list(b) do
  #  a 
  #  |> MapSet.new( ) 
  #  |> MapSet.difference( MapSet.new(b)) 
  #  |> MapSet.to_list( ) 
  #end
  
  @doc """
  offtime - ontime = range pulse 1.0ms-2.0ms
    
   0%    - 100%
   1.0ms - 2.0ms

  # Example

    iex> percto_servo(1, 0)
    {200, 405}
    iex> percto_servo(2, 100)
    {400, 810}
    iex> percto_servo(3, 50)
    {600, 907}

  """
  @spec percto_servo(led_no(), percent()) :: {counter(), counter()}
  def percto_servo(ledn, percent) when percent <= 0 do
    ontime = ledn * @shift_pls     # shift time to avoid simalteneous output
    offtime = ontime + @ms1_pls
    {ontime, offtime}
  end 
  def percto_servo(ledn, percent) when 100 <= percent do
    ontime = ledn * @shift_pls     # shift time to avoid simalteneous output
    offtime = ontime + @ms1_pls + @ms1_pls
    {ontime, offtime}
  end
  def percto_servo(ledn, percent) do
    ontime = ledn * @shift_pls     # shift time to avoid simalteneous output
    # 1.0ms-2.0ms:0-100%, pulse/1% * percent
    offtime = ontime + @ms1_pls + round(@ms1_pls/100 * percent)
    {ontime, offtime}
  end

  @doc """
   transform percent as a duty to counter 
   0%  - 100%
	 0   - 20ms
	 0   - 4096
	## Example

		iex> percto_duty(1, 0)
		{0, 4096}
		iex> percto_duty(2, 100)
		{4096, 0}
		iex> percto_duty(3, 50)
		{600, 2648}

	"""
	@spec percto_duty(led_no(), percent()) :: {counter(), counter()}
  def percto_duty(_ledn, percent) when percent <= 0, do: {0, 0x1000}    # all off
  def percto_duty(_ledn, percent) when 100 <= percent, do: {0x1000, 0}  # all on
  def percto_duty(ledn, percent) do
    # 0% -100% -> 0 - 4095
    ontime = ledn * @shift_pls    # shift time to avoid simalteneous output
    offtime = round(4096/100 * percent) + ontime
    if 4096 <= offtime do
      {ontime, offtime - 4096}
    else
      {ontime, offtime}
    end
  end

  #def cntto_perc(:duty, {ontime, offtime}), do: dutyto_perc({ontime, offtime})
  #def cntto_perc(:servo, {ontime, offtime}), do: servoto_perc({ontime, offtime})

  #def binto_perc(:duty,  bindata), do: parse_led(bindata) |> dutyto_perc( )
  #def binto_perc(:servo, bindata), do: parse_led(bindata) |> servoto_perc( )

  @doc """
    Transform counters as a servo to percent in case of 50Hz-20ms pulse 
    
    # Example 
      iex> servoto_perc({200, 405})  
      0   
      iex> servoto_perc({300, 505 + 102})  
      50   
      iex> servoto_perc({400, 605 + 205})  
      100  
      iex> servoto_perc({4000, (205 + 102 - (4096 - 4000))})  
      50  

  """
	@spec servoto_perc({counter(), counter()}) :: percent()
	def servoto_perc({ontime, offtime}) when offtime < ontime, do: servoto_perc({ontime, offtime + 4096})
	def servoto_perc({ontime, offtime}) when (offtime - ontime) <= @ms1_pls, do: 0
	def servoto_perc({ontime, offtime}) when (@ms1_pls + @ms1_pls) <= (offtime - ontime), do: 100
	def servoto_perc({ontime, offtime}) do
		width = offtime - ontime
		outpulse = width - @ms1_pls
		round((outpulse * 100)/@ms1_pls)
	end

  @doc """
    Transform counters as a duty to percent
    when ontime is over 4096, it is 100%
    when offtime is over 4096, it is 0%
    width of counters : 4096 = percent : 100

    #Example
    
      iex> dutyto_perc({0, 4096})  
      0  
      iex> dutyto_perc({4096, 0})  
      100  
      iex> dutyto_perc({100, 100 + 2048})  
      50  
      iex> dutyto_perc({100 + 2048, 100})  
      50  
      iex> dutyto_perc({200, 200 + 1024})  
      25  
      
  """
	@spec dutyto_perc({counter(), counter()}) :: percent()
	def dutyto_perc({ontime, _offtime}) when 4096 <= ontime, do: 100
	def dutyto_perc({_ontime, offtime}) when 4096 <= offtime, do: 0
	def dutyto_perc({ontime, offtime}) do
		width = if offtime >= ontime, do: offtime - ontime, else: offtime + 4096 - ontime
		round(width * 100/4096)
	end
end
