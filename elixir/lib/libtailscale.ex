defmodule Libtailscale do
  @on_load :init

  @appname :libtailscale
  @libname "libtailscale"

  def init do
    so_name =
      case :code.priv_dir(@appname) do
        {:error, :bad_name} ->
          case File.dir?(Path.join(["..", :priv])) do
            true ->
              Path.join(["..", :priv, @libname])

            _ ->
              Path.join([:priv, @libname])
          end

        dir ->
          Path.join(dir, @libname)
      end

    :erlang.load_nif(so_name, 0)
  end

  def new() do
    not_loaded(:new)
  end

  def start(_ts) do
    not_loaded(:start)
  end

  def up(_ts) do
    not_loaded(:up)
  end

  def close(_ts) do
    not_loaded(:close)
  end

  def set_dir(_ts, _dir) do
    not_loaded(:set_dir)
  end

  def set_hostname(_ts, _hostname) do
    not_loaded(:set_hostname)
  end

  def set_authkey(_ts, _authkey) do
    not_loaded(:set_authkey)
  end

  def set_control_url(_ts, _control_url) do
    not_loaded(:set_control_url)
  end

  def set_ephemeral(_ts, _ephemeral) do
    not_loaded(:set_ephemeral)
  end

  def set_logfd(_ts, _logfd) do
    not_loaded(:set_logfd)
  end

  def getips(_ts) do
    not_loaded(:getips)
  end

  def dial(_ts, _network, _addr) do
    not_loaded(:dial)
  end

  def listen(_ts, _network, _addr) do
    not_loaded(:listen)
  end

  def getremoteaddr(_ts, _listener, _conn) do
    not_loaded(:getremoteaddr)
  end

  def accept(_ts, _listener) do
    not_loaded(:accept)
  end

  def read(_ts, _conn, _len) do
    not_loaded(:read)
  end

  def write(_ts, _conn, _bin) do
    not_loaded(:write)
  end

  def close_connection(_ts, _conn) do
    not_loaded(:close_connection)
  end

  def close_listener(_ts, _conn) do
    not_loaded(:close_listener)
  end

  def loopback(_ts) do
    not_loaded(:loopback)
  end

  defp not_loaded(line) do
    :erlang.nif_error({:not_loaded, [{:module, __MODULE__}, {:function, line}]})
  end
end
