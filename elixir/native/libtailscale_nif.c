#include <erl_nif.h>
#include <errno.h>
#include <unistd.h>
#include <stdint.h>
#include "tailscale.h"

ERL_NIF_TERM atom_ok;
ERL_NIF_TERM atom_error;
ERL_NIF_TERM atom_ebadf;

static char* binary_to_string(ErlNifBinary* bin) {
  char* s = malloc(bin->size * sizeof(char) + 1);
  memcpy(s, (const char*)bin->data, bin->size);
  s[bin->size] = '\0';

  return s;
}

static ERL_NIF_TERM return_errmsg(ErlNifEnv* env, tailscale sd) {
  char errmsg[512];
  /* Only read 511 characters here and insert 0 at the end. */
  if (tailscale_errmsg(sd, errmsg, 511) != 0) {
    return enif_make_badarg(env);
  }
  errmsg[511] = '\0';

  /* Safe because of the NULL inserted above. */
  size_t len = strlen(errmsg);

  ERL_NIF_TERM return_binary;
  unsigned char* return_binary_data = enif_make_new_binary(env, len, &return_binary);

  memcpy((char * restrict)return_binary_data, errmsg, len);

  return enif_make_tuple2(env, atom_error, return_binary);
}

static ERL_NIF_TERM tailscale_new_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;

  if (argc != 0) {
    return enif_make_badarg(env);
  }

  sd = tailscale_new();
  return enif_make_int(env, sd);
}

static ERL_NIF_TERM tailscale_start_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;

  if (argc != 1 || !enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if (tailscale_start(sd) != 0) {
    return return_errmsg(env, sd);
  } else {
    return atom_ok;
  }
}

static ERL_NIF_TERM tailscale_up_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;

  if (argc != 1 || !enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if (tailscale_up(sd) != 0) {
    return return_errmsg(env, sd);
  } else {
    return atom_ok;
  }
}

static ERL_NIF_TERM tailscale_close_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;

  if (argc != 1 || !enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  int res = tailscale_close(sd);
  if (res == EBADF) {
    return enif_make_tuple2(env, atom_error, atom_ebadf);
  } else if (res != 0) {
    return return_errmsg(env, sd);
  } else {
    return atom_ok;
  }
}

static ERL_NIF_TERM tailscale_set_dir_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;
  ErlNifBinary bin;

  if (argc != 2) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_inspect_binary(env, argv[1], &bin)) {
    return enif_make_badarg(env);
  }

  char* dir = binary_to_string(&bin);

  int ret = tailscale_set_dir(sd, dir);
  free(dir);

  if (ret != 0) {
    return return_errmsg(env, sd);
  } else {
    return atom_ok;
  }
}

static ERL_NIF_TERM tailscale_set_hostname_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;
  ErlNifBinary bin;

  if (argc != 2) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_inspect_binary(env, argv[1], &bin)) {
    return enif_make_badarg(env);
  }

  char* hostname = binary_to_string(&bin);

  int ret = tailscale_set_hostname(sd, hostname);

  free(hostname);

  if (ret != 0) {
    return return_errmsg(env, sd);
  } else {
    return atom_ok;
  }

}

static ERL_NIF_TERM tailscale_set_authkey_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  int sd;
  ErlNifBinary bin;

  if (argc != 2) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_inspect_binary(env, argv[1], &bin)) {
    return enif_make_badarg(env);
  }

  char* authkey = binary_to_string(&bin);

  int ret = tailscale_set_authkey(sd, authkey);

  free(authkey);

  if (ret != 0) {
    return return_errmsg(env, sd);
  } else {
    return atom_ok;
  }

}

static ERL_NIF_TERM tailscale_set_control_url_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  int sd;
  ErlNifBinary bin;

  if (argc != 2) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_inspect_binary(env, argv[1], &bin)) {
    return enif_make_badarg(env);
  }

  char* control_url = binary_to_string(&bin);

  int ret = tailscale_set_control_url(sd, control_url);

  free(control_url);

  if (ret != 0) {
    return return_errmsg(env, sd);
  } else {
    return atom_ok;
  }

}

static ERL_NIF_TERM tailscale_set_ephemeral_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  int sd, ephemeral;

  if (argc != 2) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[1], &ephemeral)) {
    return enif_make_badarg(env);
  }

  if (tailscale_set_ephemeral(sd, ephemeral) != 0) {
    return return_errmsg(env, sd);
  } else {
    return atom_ok;
  }

}

static ERL_NIF_TERM tailscale_set_logfd_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  int sd, fd;

  if (argc != 2) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[1], &fd)) {
    return enif_make_badarg(env);
  }

  if (tailscale_set_logfd(sd, fd) != 0) {
    return return_errmsg(env, sd);
  } else {
    return atom_ok;
  }
}

static ERL_NIF_TERM tailscale_getips_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  int sd;
  ERL_NIF_TERM ret;
  size_t len;
  char* data;
  char buffer[512];

  if (argc != 1) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if (tailscale_getips(sd, buffer, 512)) {
    return return_errmsg(env, sd);
  }

  buffer[511] = '\0';
  len = strlen(buffer);

  data = (char*)enif_make_new_binary(env, strlen(buffer), &ret);

  memcpy(data, buffer, len);

  return enif_make_tuple2(env, atom_ok, ret);
}

static ERL_NIF_TERM tailscale_dial_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  int sd;
  ErlNifBinary network_bin;
  ErlNifBinary addr_bin;
  tailscale_conn conn;

  if (argc != 3) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_inspect_binary(env, argv[1], &network_bin)) {
    return enif_make_badarg(env);
  }

  char* network = binary_to_string(&network_bin);

  if(!enif_inspect_binary(env, argv[2], &addr_bin)) {
    return enif_make_badarg(env);
  }
  char* addr = binary_to_string(&addr_bin);

  int ret = tailscale_dial(sd, network, addr, &conn);

  free(addr);
  free(network);

  if (ret != 0) {
    return return_errmsg(env, sd);
  } else {
    return enif_make_tuple2(env, atom_ok, conn);
  }
}

static ERL_NIF_TERM tailscale_listen_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  int sd;
  ErlNifBinary network_bin;
  ErlNifBinary addr_bin;
  tailscale_listener listener;

  if (argc != 3) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_inspect_binary(env, argv[1], &network_bin)) {
    return enif_make_badarg(env);
  }
  char* network = binary_to_string(&network_bin);

  if(!enif_inspect_binary(env, argv[2], &addr_bin)) {
    return enif_make_badarg(env);
  }
  char* addr = binary_to_string(&addr_bin);

  int ret = tailscale_listen(sd, network, addr, &listener);

  free(addr);
  free(network);

  if (ret != 0) {
    return return_errmsg(env, sd);
  } else {
    return enif_make_tuple2(env, atom_ok, enif_make_int(env, listener));
  }
}

static ERL_NIF_TERM tailscale_getremoteaddr_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;
  tailscale_listener listener;
  tailscale_conn conn;
  ERL_NIF_TERM ret;
  size_t len;
  char* data;
  char buffer[512];

  if (argc != 3) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[1], &listener)) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[2], &conn)) {
    return enif_make_badarg(env);
  }

  if (tailscale_getremoteaddr(listener, conn, buffer, 512)) {
    return return_errmsg(env, sd);
  }

  buffer[511] = '\0';
  len = strlen(buffer);

  data = (char*)enif_make_new_binary(env, strlen(buffer), &ret);

  memcpy(data, buffer, len);

  return enif_make_tuple2(env, atom_ok, ret);
}

static ERL_NIF_TERM tailscale_accept_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;
  tailscale_conn conn;
  tailscale_listener listener;

  if (argc != 2) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[1], &listener)) {
    return enif_make_badarg(env);
  }


  int res = tailscale_accept(listener, &conn);
  if (res == EBADF) {
    return enif_make_tuple2(env, atom_error, atom_ebadf);
  } else if (res != 0) {
    return return_errmsg(env, sd);
  } else {
    return enif_make_tuple2(env, atom_ok, enif_make_int(env, conn));
  }
}

static ERL_NIF_TERM tailscale_read_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;
  tailscale_conn conn;
  int64_t len;
  ssize_t ret;
  ErlNifBinary binary;


  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[1], &conn)) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int64(env, argv[2], &len)) {
    return enif_make_badarg(env);
  }

  if(!enif_alloc_binary(len, &binary)) {
    return enif_make_badarg(env);
  }

  ret = read(conn, binary.data, len);
  if (ret > 0) {
    // Read successful
    if (!enif_realloc_binary(&binary, (size_t)ret)) {
      return enif_make_badarg(env);
    }

    return enif_make_tuple2(env, atom_ok, enif_make_binary(env, &binary));
  } else if (ret < 0) {
    // Read failed
    return enif_make_badarg(env);
  } else {
    // Nothing returned
    return atom_ok;
  }
}

static ERL_NIF_TERM tailscale_write_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;
  tailscale_conn conn;
  ssize_t ret;
  ErlNifBinary binary;

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[1], &conn)) {
    return enif_make_badarg(env);
  }

  if (!enif_inspect_binary(env, argv[2], &binary)) {
    return enif_make_badarg(env);
  }

  if ((ret = write(conn, binary.data, binary.size)) < 0) {
    // An error occurred
    return enif_make_badarg(env);
  }

  return enif_make_tuple2(env, atom_ok, enif_make_int(env, ret));
}

static ERL_NIF_TERM tailscale_close_connection_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;
  tailscale_conn conn;

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[1], &conn)) {
    return enif_make_badarg(env);
  }

  if(close(conn) != 0) {
    // An error occurred
    return enif_make_badarg(env);
  }

  return atom_ok;
}

static ERL_NIF_TERM tailscale_close_listener_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;
  tailscale_listener listener;

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[1], &listener)) {
    return enif_make_badarg(env);
  }

  if(close(listener) != 0) {
    // An error occurred
    return enif_make_badarg(env);
  }

  return atom_ok;
}

static ERL_NIF_TERM tailscale_loopback_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  tailscale sd;
  char addr_buf[256];
  char proxy_cred[33];
  char local_api_cred[33];
  ERL_NIF_TERM addr_term, proxy_cred_term, local_api_cred_term;
  size_t addr_len, proxy_cred_len, local_api_cred_len;
  char* addr_data;
  char* proxy_cred_data;
  char* local_api_cred_data;

  if (argc != 1) {
    return enif_make_badarg(env);
  }

  if(!enif_get_int(env, argv[0], &sd)) {
    return enif_make_badarg(env);
  }

  if (tailscale_loopback(sd, addr_buf, 256, proxy_cred, local_api_cred) != 0) {
    return return_errmsg(env, sd);
  }

  addr_buf[255] = '\0';
  proxy_cred[32] = '\0';
  local_api_cred[32] = '\0';

  addr_len = strlen(addr_buf);
  proxy_cred_len = strlen(proxy_cred);
  local_api_cred_len = strlen(local_api_cred);

  addr_data = (char*)enif_make_new_binary(env, addr_len, &addr_term);
  proxy_cred_data = (char*)enif_make_new_binary(env, proxy_cred_len, &proxy_cred_term);
  local_api_cred_data = (char*)enif_make_new_binary(env, local_api_cred_len, &local_api_cred_term);

  memcpy(addr_data, addr_buf, addr_len);
  memcpy(proxy_cred_data, proxy_cred, proxy_cred_len);
  memcpy(local_api_cred_data, local_api_cred, local_api_cred_len);

  return enif_make_tuple2(env, atom_ok, enif_make_tuple3(env, addr_term, proxy_cred_term, local_api_cred_term));
}

static int load(ErlNifEnv* env, void** priv, ERL_NIF_TERM load_info)
{
  atom_ok = enif_make_atom(env, "ok");
  atom_error = enif_make_atom(env, "error");
  atom_ebadf = enif_make_atom(env, "ebadf");

  *priv = NULL; // No module-level private data needed for this example

  return 0;
}

// Unload callback: Called when the NIF library is unloaded (e.g., code purge)
static void unload(ErlNifEnv* env, void* priv_data) {
  // Perform any necessary cleanup of module-level private data if it existed
  fprintf(stderr, "NIF: Library unloaded\n");
}

static ErlNifFunc nif_funcs[] = {
  {"new", 0, tailscale_new_nif},
  {"start", 1, tailscale_start_nif},
  {"up", 1, tailscale_up_nif},
  {"close", 1, tailscale_close_nif},
  {"set_dir", 2, tailscale_set_dir_nif},
  {"set_hostname", 2, tailscale_set_hostname_nif},
  {"set_authkey", 2, tailscale_set_authkey_nif},
  {"set_control_url", 2, tailscale_set_control_url_nif},
  {"set_ephemeral", 2, tailscale_set_ephemeral_nif},
  {"set_logfd", 2, tailscale_set_logfd_nif},
  {"getips", 1, tailscale_getips_nif},
  {"dial", 3, tailscale_dial_nif},
  {"listen", 3, tailscale_listen_nif},
  {"getremoteaddr", 3, tailscale_getremoteaddr_nif},
  {"accept", 2, tailscale_accept_nif},
  {"read", 3, tailscale_read_nif},
  {"write", 3, tailscale_write_nif},
  {"close_connection", 2, tailscale_close_connection_nif},
  {"close_listener", 2, tailscale_close_listener_nif},
  {"loopback", 1, tailscale_loopback_nif},
};

ERL_NIF_INIT(Elixir.Libtailscale, nif_funcs, &load, NULL, NULL, unload)
