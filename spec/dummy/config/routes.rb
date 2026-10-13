# frozen_string_literal: true

Rails.application.routes.draw do
  root "searches#show"
  post "search", to: "searches#search", as: :search
  post "open", to: "searches#open", as: :open_record
  post "suggest", to: "searches#suggest", as: :suggest
  get "elsewhere", to: "searches#elsewhere"
end
