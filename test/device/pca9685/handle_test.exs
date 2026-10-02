defmodule DevcontrolI2c.PCA9685.HandleTest do
  #use ExUnit.Case, async: false
  use ExUnit.Case
  doctest DevcontrolI2c.PCA9685.Handle, import: true
  alias DevcontrolI2c.PCA9685.Handle
  alias DevcontrolI2c.PCA9685.Device
  #alias DevcontrolI2c.DevTable
  alias FsmDiagram, as: Fsm

  @tbl_fsmids [{"i2c-0", 0x40}, {"i2c-1", 0x40}, {"i2c-2", 0x40}]
  setup_all do
    # test waits until all tasks are activated
    wait_task(@tbl_fsmids)
  end
  defp wait_task([]), do: :ok
  defp wait_task(fsmid_list) do
    fsm_list = 
      Enum.reduce(fsmid_list, fsmid_list, 
          fn fsmid, acc -> 
              pid = Fsm.get_fsmpid(fsmid)
              if is_pid(pid) do
                acc -- [fsmid]
              else
                acc
              end
          end)  
    Process.sleep(10)
    wait_task(fsm_list)
  end
  #setup_all do 
    #{:ok, bus1} = Circuits.I2C.open("i2c-1")
    #{:ok, bus2} = Circuits.I2C.open("i2c-2")
    #fsm1 = {"i2c-1", 0x40}
    #fsm2 = {"i2c-2", 0x40}
    #{:ok, pid1} = Handle.start(fsm1, bus1)
    #{:ok, pid2} = Handle.start(fsm2, bus2)
    #Process.sleep(10)
    #assert( pid1 == Fsm.get_fsmpid(fsm1)) 
    #assert( pid2 == Fsm.get_fsmpid(fsm2))
    #assert({fsm1, bus1} == Fsm.get_elm(fsm1, :vars))
    #assert({fsm2, bus2} == Fsm.get_elm(fsm2, :vars))
    #Handle.api_format()    # check if it exists
    #Process.sleep(100)
    #on_exit(fn -> ending(pid1)
    #              ending(pid2)
    #end)
  #end
  #defp ending(pid) do
  #  if Process.alive?(pid) do
  #    ref = Process.monitor(pid)
  #    Process.exit(pid, :shutdown)
  #    receive do
  #      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
  #    after
  #      1_000 -> Process.exit(pid, :kill) #
  #    end
  #  end
  #end
  
  #test "read device table" do 
  #  table = DevTable.get_table({"i2c-1", 0x40})
  #  assert(Handle.table1() == table)
  #  table = DevTable.get_table({"i2c-2", 0x40})
  #  assert(Handle.table2() == table)
  #end
  test "check if functions exists" do
    Handle.api_format()
  end
  test "ledoutto_bin() invalid check" do
    assert(Handle.ledoutto_bin({3}) == <<>>)
    assert(Handle.ledoutto_bin({"a", 3}) == <<>>)
    assert(Handle.ledoutto_bin({256, :bb}) == <<>>)
  end

  @testtbl [{0, [30, 40, 50]}, {3, 60}, {4, 70}, {5, [80, 90]}, {7, [10, 20, 30, 40, 50, 60, 70, 80, 90]}]
  test "ledout duty pwmcontrol test" do
    func = Fsm.get_elm({"i2c-1", 0x40}, :func)
    assert(func == &Handle.wait_req/1)
    pid = Fsm.get_fsmpid({"i2c-1", 0x40})
    Enum.each(@testtbl, fn {ledn, percents} ->
      send(pid, {:duty_out, self(), ledn, percents})
      if is_list(percents) do
        send(pid, {:get_counter, self(), ledn, length(percents)})
      else
        send(pid, {:get_counter, self(), ledn, 1})
      end
      counters = 
        receive do
          {:reply, _from, ^ledn, data} -> data
        after 100 -> 
          IO.puts("Timeout waiting for response from ledout")
          {:error, :timeout}
        end
      result = 
        if is_tuple(counters) do
          Device.dutyto_perc(counters) 
        else
          Enum.map(counters, fn counter -> Device.dutyto_perc(counter) end) 
        end
      assert(percents == result)
    end)
  end

  test "ledout servo control test" do
    pid = Fsm.get_fsmpid({"i2c-1", 0x40})
    Enum.each(@testtbl, fn {ledn, percents} ->
      send(pid, {:servo_out, self(), ledn, percents})
      if is_list(percents) do
        send(pid, {:get_counter, self(), ledn, length(percents)})
      else
        send(pid, {:get_counter, self(), ledn, 1})
      end
      counters = 
        receive do
          {:reply, _from, ^ledn, data} -> data
        after 100 -> 
          IO.puts("Timeout waiting for response from ledout")
          {:error, :timeout}
        end
      result = 
        if is_tuple(counters) do
          Device.servoto_perc(counters) 
        else
          Enum.map(counters, fn counter -> Device.servoto_perc(counter) end) 
        end
      assert(percents == result)
    end)
  end

  @testtbl_counters [{0, {0, 2047}}, {1, {2047, 2047}}, {2, { 1000, 3047}}] 
  @result_counters  [{0, {0, 2047}}, {1, {0, 4096}}, {2, { 1000, 3047}}] 
  test "set counter test" do
    pid = Fsm.get_fsmpid({"i2c-2", 0x40})
    Enum.with_index(@testtbl_counters, fn {ledn, counters}, index -> 
      send(pid, {:set_counter, self(), ledn, counters})
      
      if is_list(counters) do
        send(pid, {:get_counter, self(), ledn, length(counters)})
      else
        send(pid, {:get_counter, self(), ledn, 1})
      end
      counters = 
        receive do
          {:reply, _from, ^ledn, data} -> data
        after 100 -> 
          IO.puts("Timeout waiting for response from ledout")
          {:error, :timeout}
        end
      assert({ledn, counters} == Enum.at(@result_counters, index))
    end)
  end
  test "illegal event code test" do
    pid = Fsm.get_fsmpid({"i2c-1", 0x40})
    send(pid, {:test, self(), 1, 30}) 
    send(pid, {:test, self(), 1})
    send(pid, {:get_counter, self(), 3, 0})
    receive do
      {:reply, _from, 3, {_on, _off}} -> true
      _ -> false
    end
    |> assert()
    send(pid, {:get_counter, self(), 14, 5})
    receive do
      {:reply, _from, 14, data} when is_list(data) -> 
      if length(data) == 2 do
        Enum.all?(data, fn d -> {_,_} = d end)
      else
        false
      end
    end
    |> assert()

  end
end
