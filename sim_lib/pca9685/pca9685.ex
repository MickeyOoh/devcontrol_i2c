defmodule CircuitsSim.Device.PCA9685 do

  @moduledoc """
  PCA9685 16-channel 12 bit PWM and led driver 

  This is normally found at I2C addresses between 0x40.

  See the [datasheet](https://www.nxp.com/products/power-drivers/lighting-driver-and-controller-ics/led-drivers/16-channel-12-bit-pwm-fm-plus-ic-bus-led-driver:PCA9685) for details.
  Many features aren't implemented.
  """
  alias CircuitsSim.I2C.I2CDevice
  alias CircuitsSim.I2C.I2CServer

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(args) do
    device = __MODULE__.new()
    I2CServer.child_spec_helper(device, args)
  end

  @spec set_counts(String.t(), Circuits.I2C.address(), list()) :: :ok
  def set_counts(bus_name, address, {outdata, pwmdata}) when is_list(outdata) and is_list(pwmdata) do
    I2CServer.send_message(bus_name, address, {:set_data, {outdata, pwmdata}})
  end

  # 0-68 70regs- 70 * 8 = 560bits, 250-255 6regs- 6 * 8 = 48bits
  #defstruct holdreg: 0, data: <<0::binary-size(256)>>
  @mode1 <<0x11>>   # default value
  @mode2 <<0x04>>   # default value
  @sub_addrs <<0xe2, 0xe4, 0xe8, 0xe0>>
  @led_registers String.duplicate(<<0x00>>, 250)

  @initial_memory @mode1 <> @mode2 <> @sub_addrs <> @led_registers
  @outdata List.duplicate([0,0], 16)
  @pwmdata List.duplicate(0,16)  
  defstruct holdreg: 0, data: @initial_memory, prescale: 0, outdata: @outdata, pwmdata: @pwmdata 
 
  @spec new() :: %__MODULE__{}
  def new() do
    %__MODULE__{}
  end

  ## protocol implementation
  defimpl I2CDevice do
    @impl I2CDevice
    def read(state, count) do
      regno = Map.get(state, :holdreg)
      data = Map.get(state, :data)
      cond do
        regno + count <= 70 ->
            target = binary_part(data, regno, count)
            {{:ok, target}, state}
        250 <= regno and regno + count <= 256 ->
            target = binary_part(data, regno, count)
            {{:ok, target}, state}
        true ->
            {{:error, <<0>>}, state}
      end
    end

    @impl I2CDevice
    def write(state, <<_regno::binary-size(1), setdata::binary>> = data) do
      regno = :binary.at(data, 0)   # register No 
      state = %{state | holdreg: regno}
      bindata = Map.get(state, :data)
      num = byte_size(setdata)
      cond do
        num <= 0 -> state
        regno + num <= 70 ->
          <<pre::binary-size(regno), _odat::binary-size(num), rest::binary>> = bindata
          tmp = <<pre::binary-size(regno), setdata::binary-size(num), rest::binary>>
          %{state | data: tmp}
        250 <= regno and regno + num <= 254 ->
          <<pre::binary-size(regno), _o::binary-size(num), rest::binary>> = bindata
          tmp = <<pre::binary-size(regno), setdata::binary-size(num), rest::binary>>
          offset = rem(regno, 250)
          lednolist = Enum.to_list(0..15)
          tmp = Enum.reduce(lednolist, tmp, fn ledno, tmp ->
              regno = 6 + ledno * 4 + offset
              <<pre::binary-size(regno), _o::binary-size(num), rest::binary>> = tmp
              <<pre::binary-size(regno), setdata::binary-size(num), rest::binary>>
            end)
          %{state | data: tmp}
        254 <= regno and regno + num <= 256 ->
          <<pre::binary-size(regno), _o::binary-size(num), rest::binary>> = bindata
          tmp = <<pre::binary-size(regno), setdata::binary-size(num), rest::binary>>
          %{state | data: tmp}
        true ->
          state
      end
    end
    def write(state, _), do: state

    @impl I2CDevice
    def write_read(state, data, count) do
        state
        |> write(data)
        |> read(count)
    end

    @impl I2CDevice
    def render(state) do
      "PCA9685 (Address: #{inspect(state)})"
    end

    #@impl I2CDevice
    #def snapshot(state) do
    #  state
    #end

    #defp reg_map() do
    #%{
    #    0 => {:regmode1, [a: 8], "mode_1"},
    #  }
    #end
    #@impl I2CDevice
    #def handle_message(state, {:set_humidity_rh, value}) do
    #  {:ok, %{state | humidity_rh: value}}
    #end

    @impl I2CDevice
    def handle_message(state, {:set_data, {outdata, pwmdata} }) do
      #{:ok, %{state | outdata: value}}
      {:ok, %{state | outdata: outdata, pwmdata: pwmdata} }
    end

    def handle_message(state, {:get_data, :data}) do
      value = Map.get(state, :data)
      {value, state}
    end
  end
end
