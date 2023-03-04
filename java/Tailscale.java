package com.tailscale;

import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.URI;
import java.net.Socket;
import java.net.SocketAddress;
import java.net.ServerSocket;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.PrintWriter;
import java.io.BufferedReader;
import java.util.Base64;
import java.net.PasswordAuthentication;
import java.net.InetSocketAddress;

import com.tailscale.NativeUtils;

public class Tailscale {
	static {
		try {
			System.loadLibrary("libtailscale");
			System.loadLibrary("libtailscalejni");
		} catch (UnsatisfiedLinkError e) {
			try {
				NativeUtils.loadLibraryFromJar("/" + System.mapLibraryName("tailscale"));
				NativeUtils.loadLibraryFromJar("/" + System.mapLibraryName("tailscalejni"));
			} catch (IOException ex) {
				throw new RuntimeException(ex);
			}
		}
	}

	public static class LocalAPI {
		private String addr;
		private String auth;

		LocalAPI(String addr, String auth) {
			this.addr = addr;
			this.auth = auth;
		}

		public void status() throws IOException, InterruptedException {
			URI uri = URI.create(this.addr + "/localapi/v0/status");

			HttpClient client = HttpClient.newHttpClient();
			HttpRequest request = HttpRequest.newBuilder()
			.uri(uri)
			.header("Sec-Tailscale", "localapi")
			.header("Authorization", "Basic " + this.auth)
			.build();
			HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
			System.out.println(response.statusCode());
			System.out.println(response.body());
		}
	}

	// Handle is a low-level interface to the libtailscale `tailscale` object.
	// Errors are thrown as RuntimeException objects.
	public static class Handle {
		private final int sd;
		InetSocketAddress loopbackSocketAddr;
		String loopbackAddr;
		String proxyPassword;
		String localAPIAuth;

		// Handle allocates a new Tailscale handle by calling tailscale_new.
		public Handle() {
			this.sd = tailscaleNew();
		}

		// up calls tailscale_up.
		public void up() {
			if (Tailscale.up(this.sd) != 0) {
				throw new RuntimeException("Tailscale.up: " + errmsg(this.sd));
			}
		}

		// disableLog calls tailscale_set_logfd with -1, to disable logging.
		public void disableLog() {
			if (Tailscale.disableLog(this.sd) != 0) {
				throw new RuntimeException("Tailscale.disableLog: " + errmsg(this.sd));
			}
		}

		// close calls tailscale_close.
		public void close() {
			if (Tailscale.close(this.sd) != 0) {
				throw new RuntimeException("Tailscale.close: " + errmsg(this.sd));
			}
		}

		// setDir calls tailscale_set_dir.
		public void setDir(String dir) {
			if (Tailscale.setDir(this.sd, dir) != 0) {
				throw new RuntimeException("Tailscale.setDir: " + errmsg(this.sd));
			}
		}

		// setHostname calls tailscale_set_hostname.
		public void setHostname(String hostname) {
			if (Tailscale.setHostname(this.sd, hostname) != 0) {
				throw new RuntimeException("Tailscale.setHostname: " + errmsg(this.sd));
			}
		}

		// setAuthkey calls tailscale_set_authkey.
		public void setAuthkey(String authkey) {
			if (Tailscale.setAuthkey(this.sd, authkey) != 0) {
				throw new RuntimeException("Tailscale.setAuthkey: " + errmsg(this.sd));
			}
		}

		// setControlURL calls tailscale_set_control_url.
		public void setControlURL(String controlURL) {
			if (Tailscale.setControlURL(this.sd, controlURL) != 0) {
				throw new RuntimeException("Tailscale.setControlURL: " + errmsg(this.sd));
			}
		}

		// setEphemeral calls tailscale_set_ephemeral.
		public void setEphemeral(boolean val) {
			if (Tailscale.setEphemeral(this.sd, val) != 0) {
				throw new RuntimeException("Tailscale.setEphemeral: " + errmsg(this.sd));
			}
		}

		// loopback calls tailscale_loopback and initializes the addr/localCred/proxyCred parameters.
		public void loopback() throws IOException, InterruptedException {
			byte[] proxyCred = new byte[33];
			byte[] localCred = new byte[33];
			String addr = Tailscale.loopback(this.sd, proxyCred, localCred);
			if (addr == null) {
				throw new RuntimeException("Tailscale.loopback: " + errmsg(this.sd));
			}
			this.loopbackAddr = "http://" + addr;
			// final byte of each array is a NUL-terminator
			this.proxyPassword = new String(proxyCred).substring(0, 32);
			String local = new String(localCred).substring(0, 32);
			this.localAPIAuth = Base64.getEncoder().encodeToString((":"+local).getBytes());

			try {
				URI uri = new URI(this.loopbackAddr);
				String host = uri.getHost();
				int port = uri.getPort();
				this.loopbackSocketAddr = new InetSocketAddress(host, port);
			} catch (Exception e) {
				throw new RuntimeException(e);
			}
		}

		public LocalAPI localAPI() throws IOException, InterruptedException {
			if (this.loopbackAddr == null) {
				this.loopback();
			}
			return new LocalAPI(this.loopbackAddr, this.localAPIAuth);
		}

		// dial calls tailscale_dial.
		public HandleConn dial(String network, String addr) {
			int c = Tailscale.dial(this.sd, network, addr);
			if (c == -1) {
				throw new RuntimeException("Tailscale.dial: " + errmsg(this.sd));
			}
			return new Tailscale.HandleConn(c, this.sd);
		}

		public HandleListener listen(String network, String addr) {
			int ln = Tailscale.listen(this.sd, network, addr);
			if (ln == -1) {
				throw new RuntimeException("Tailscale.dial: " + errmsg(this.sd));
			}
			return new Tailscale.HandleListener(ln, this.sd);
		}

		public InetSocketAddress proxyAddr() {
			return this.loopbackSocketAddr;
		}
		public PasswordAuthentication proxyAuth() {
			return new PasswordAuthentication("tsnet", this.proxyPassword.toCharArray());
		}
	}

	// HandleConn is a low-level interface to tailscale_conn.
	public static class HandleConn {
		private int conn;
		private int sd;

		HandleConn(int conn, int sd) {
			this.conn = conn;
			this.sd = sd;
		}

		public InputStream getInputStream() throws IOException {
			// TODO: windows support
			return new FileInputStream("/dev/fd/" + Integer.toString(conn));
		}

		public OutputStream getOutputStream() throws IOException {
			// TODO: windows support
			return new FileOutputStream("/dev/fd/" + Integer.toString(conn));
		}
	}

	// HandleListener is a low-level interface to tailscale_listener.
	public static class HandleListener {
		private int ln;
		private int sd;

		HandleListener(int ln, int sd) {
			this.ln = ln;
			this.sd = sd;
		}

		// close calls tailscale_listener_close.
		public void close() {
			if (Tailscale.listenerClose(this.ln) != 0) {
				throw new RuntimeException("Tailscale.Listener.close: " + errmsg(this.sd));
			}
		}

		// accept calls tailscale_accept.
		public HandleConn accept() {
			int c = Tailscale.accept(ln);
			if (c == -1) {
				throw new RuntimeException("Tailscale.accept: " + errmsg(this.sd));
			}
			return new HandleConn(c, this.sd);
		}

		public ServerSocket serverSocket() throws IOException {
			return new ListenerServerSocket(this);
		}
	}

	private static class ListenerServerSocket extends ServerSocket {
		private final HandleListener ln;
		ListenerServerSocket(HandleListener ln) throws IOException { this.ln = ln; }
		@Override
		public Socket accept() throws IOException {
			return new ConnSocket(this.ln.accept());
		}
		@Override
		public void bind(SocketAddress endpoint) throws IOException { this.bind(endpoint, 0); }
		@Override
		public void bind(SocketAddress endpoint, int backlog) throws IOException {
			throw new IOException("Tailscale ServerSocket already bound");
		}
		@Override
		public void close() {
			ln.close();
		}
	}

	private static class ConnSocket extends Socket {
		private final HandleConn conn;
		ConnSocket(HandleConn conn) { this.conn = conn; }
		@Override
		public InputStream getInputStream() throws IOException {
			return this.conn.getInputStream();
		}
		@Override
		public OutputStream getOutputStream() throws IOException {
			return this.conn.getOutputStream();
		}
	}

	static native int tailscaleNew(); // returns tailscale descriptor or -1
	static native int up(int sd);
	static native int close(int sd);
	static native int disableLog(int sd);
	static native int setDir(int sd, String dir);
	static native int setHostname(int sd, String hostname);
	static native int setAuthkey(int sd, String authkey);
	static native int setControlURL(int sd, String control_url);
	static native int setEphemeral(int sd, boolean ephemeral);
	static native int dial(int sd, String network, String addr);  // returns conn int or -1
	static native int listen(int sd, String network, String adr); // returns listener int or -1
	static native int listenerClose(int ln);
	static native int accept(int ln); // returns conn int or -1

	static native String loopback(int sd, byte[] proxyOut, byte[] localOut);
	static native String errmsg(int sd);
}
