class HealthController < ApplicationController
  def show
    render json: {
      status: "ok",
      app: "hello-ci",
      message: "hello from image v3"
    }
  end
end
