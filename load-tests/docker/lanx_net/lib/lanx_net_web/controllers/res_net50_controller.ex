defmodule LanxNetWeb.ResNet50Controller do
  use LanxNetWeb, :controller

  def put(conn, _params) do
    {:ok, image, _} = Plug.Conn.read_body(conn)

    predictions =
      image
      |> StbImage.read_binary!()
      |> StbImage.to_nx()
      |> then(&Nx.Serving.batched_run(LanxNet.Serving, &1))

    conn
    |> put_status(200)
    |> json(predictions)
  end
end
