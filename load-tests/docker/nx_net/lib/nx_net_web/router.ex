defmodule NxNetWeb.Router do
  use NxNetWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/predictions", NxNetWeb do
    pipe_through :api

    put "/resnet50", ResNet50Controller, :put
  end

  # Enable LiveDashboard in development

  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).

  import Phoenix.LiveDashboard.Router

  scope "/" do
    pipe_through [:fetch_session, :protect_from_forgery]

    live_dashboard "/dashboard", metrics: NxNetWeb.Telemetry
  end
end
