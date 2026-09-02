defmodule DevcontrolI2c.PCA9685Ope do
  @moduledoc """
  """

  use FsmDiagram
  require Logger
  alias DevcontrolI2c.PCA9685.Device

  def start() do
    fsm_start(__MODULE__, :init, [])
  end

  defp move_to(func, argv) do
    func = Function.capture(__MODULE__, func, 1)
    update_fnc(func, argv)
  end

  def init(argv) do
    #move_to(:initial_chip, [])
    Process.sleep(5)
    init(argv)
  end

end
