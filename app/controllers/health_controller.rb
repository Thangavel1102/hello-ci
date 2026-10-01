class HealthController < ApplicationController
  def show
    render json: {
      status: "ok",
      app: "hello-ci",
      message: "hello from image v2"
    }
  end
end
