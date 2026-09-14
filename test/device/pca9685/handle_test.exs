defmodule DevcontrolI2c.PCA9685.HandleTest do
  #use ExUnit.Case, async: false
  use ExUnit.Case
  doctest DevcontrolI2c.PCA9685.Handle
  alias DevcontrolI2c.PCA9685.Handle
  alias DevcontrolI2c.PCA9685.Device
  alias FsmDiagram, as: Fsm

  setup_all do 
    {:ok, bus1} = Circuits.I2C.open("i2c-1")
    {:ok, bus2} = Circuits.I2C.open("i2c-2")
    fsm1 = {"i2c-1", 0x40}
    fsm2 = {"i2c-2", 0x40}
    {:ok, pid1} = Handle.start(fsm1, bus1)
    {:ok, pid2} = Handle.start(fsm2, bus2)
    Process.sleep(10)
    assert( pid1 == Fsm.get_fsmpid(fsm1)) 
    assert( pid2 == Fsm.get_fsmpid(fsm2))
    assert({fsm1, bus1} == Fsm.get_elm(fsm1, :vars))
    assert({fsm2, bus2} == Fsm.get_elm(fsm2, :vars))
    on_exit(fn ->
      ending(pid1)
      ending(pid2)
    end)
  end
  defp ending(pid) do
    if Process.alive?(pid) do
      ref = Process.monitor(pid)
      Process.exit(pid, :shutdown)
      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        1_000 -> Process.exit(pid, :kill) #
      end
    end
  end

  #@testtbl [{0, 50}, {1, 30}, {2, 40}, {3, 60}, {4, 70}, {5, 80}, {6, 90}]
  @testtbl [{0, [50, 60, 70]}, {3, 50}]
  test "ledout test" do
    Process.sleep(1000)
    func = Fsm.get_elm({"i2c-1", 0x40}, :func)
    assert(func == &Handle.wait_req/1)
    pid = Fsm.get_fsmpid({"i2c-1", 0x40})
    Enum.each(@testtbl, fn {ch_no, percents} ->
      send(pid, {:duty_out, self(), ch_no, percents})
      if is_list(percents) do
        send(pid, {:get_counter, self(), ch_no, length(percents)})
      else
        send(pid, {:get_counter, self(), ch_no, 1})
      end
      counters = 
        receive do
          {:reply, _from, _no, data} -> data
        after 100 -> 
          IO.puts("Timeout waiting for response from ledout")
          {:error, :timeout}
        end
      #assert(percent == perc && ch_no == no)
      result = 
        if is_tuple(counters) do
          Device.dutyto_perc(counters) 
        else
          Enum.map(counters, fn counter -> Device.dutyto_perc(counter) end) 
        end
      assert(percents == result)
      IO.puts("result: #{inspect result}")
    end)
    Process.sleep(100)
  end

end
