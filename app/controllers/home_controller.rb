# frozen_string_literal: true

class HomeController < ApplicationController
  allow_unauthenticated only: :show

  def show
    redirect_to playlists_path if signed_in?
  end
end
