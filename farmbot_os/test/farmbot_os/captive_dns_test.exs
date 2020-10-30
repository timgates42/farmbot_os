defmodule FarmbotOS.Configurator.CaptiveDNSTest do
  use ExUnit.Case, async: false

  @dig System.find_executable("dig")

  if @dig do
    test "all dns queries resolve to local ip address" do
      {:ok, _dns_server} =
        FarmbotOS.Configurator.CaptiveDNS.start_link("lo0", 4040)

      res = :os.cmd('dig -p 4040 @127.0.0.1')

      refute to_string(res) =~ "no servers could be reached"
    end
  end
end