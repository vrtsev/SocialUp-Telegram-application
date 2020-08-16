# frozen_string_literal: true

module PdrBot
  class Controller < Telegram::AppManager::Controller
    include ControllerHelpers

    exception_handler PdrBot::ExceptionHandler

    before_action :sync_chat
    before_action :sync_user
    before_action :sync_chat_user
    before_action :authenticate_chat
    before_action :sync_message
    before_action :bot_enabled?
    around_action :with_locale

    def message(message)
      return unless message['text'].present?

      params = { chat_id: @current_chat.id, message_text: @message.text }
      result = PdrBot::Op::AutoAnswer::Random.call(params: params)
      return unless result[:answer].present?

      PdrBot::Responders::AutoAnswer.new(
        current_chat_id: @current_chat.id,
        current_message_id: @message.id,
        auto_answer: result[:answer]
      ).call
    end

    def start!
      params = { user_id: ENV['TELEGRAM_APP_OWNER_ID'] }
      result = ::PdrBot::Op::User::Find.call(params: params)
      return respond_with_error(result) unless result.success?

      PdrBot::Responders::StartMessage.new(
        current_chat_id: @current_chat.id,
        bot_author: result[:owner_user].username
      ).call
    end

    def pdr!
      params = { chat_id: @current_chat.id, user_id: @current_user.id }
      result = ::PdrBot::Op::Game::Run.call(params: params)
      return respond_with_error(result) unless result.success?

      PdrBot::Responders::Game.new(current_chat_id: @current_chat.id).call
      results!
    end

    def results!
      params = { chat_id: @current_chat.id }
      result = ::PdrBot::Op::GameRound::LatestResults.call(params: params)
      return respond_with_error(result) unless result.success?

      PdrBot::Responders::Results.new(
        current_chat_id: @current_chat.id,
        winner_full_name: result[:winner].full_name,
        loser_full_name: result[:loser].full_name
      ).call
    end

    def stats!
      params = { chat_id: @current_chat.id }
      result = ::PdrBot::Op::GameStat::ByChat.call(params: params)
      return respond_with_error(result) unless result.success?

      PdrBot::Responders::Stats.new(
        current_chat_id: @current_chat.id,
        winner_stat: result[:winner_stat],
        loser_stat: result[:loser_stat],
        chat_stats: result[:chat_stats]
      ).call
    end

    private

    def sync_chat
      params = Hashie.symbolize_keys(chat)
      result = ::PdrBot::Op::Chat::Sync.call(params: params)
      handle_callback_failure(result[:error], __method__) unless result.success?
      @current_chat = result[:chat]
    end

    def sync_user
      params = { chat_id: @current_chat.id }.merge(Hashie.symbolize_keys(from))
      result = ::PdrBot::Op::User::Sync.call(params: params)
      handle_callback_failure(result[:error], __method__) unless result.success?
      @current_user = result[:user]
    end

    def sync_chat_user
      params = { chat_id: @current_chat.id, user_id: @current_user.id }
      result = ::PdrBot::Op::ChatUser::Sync.call(params: params)
      handle_callback_failure(result[:error], __method__) unless result.success?
      @current_chat_user = result[:chat_user]
    end

    def authenticate_chat
      params = { chat_id: @current_chat.id }
      result = ::PdrBot::Op::Chat::Authenticate.call(params: params)
      handle_callback_failure(result[:error], __method__) unless result.success?

      unless result[:approved]
        ::PdrBot.logger.info "* Chat #{@current_chat.id} failed authentication".bold.red
        throw :abort
      end
    end

    def sync_message
      params = {
        chat_id: @current_chat.id,
        user_id: @current_user.id,
        message_id: payload['message_id'],
        text: payload['text'],
        date: payload['date']
      }
      result = PdrBot::Op::Message::Sync.call(params: params)
      handle_callback_failure(result[:error], __method__) unless result.success?
      @message = result[:message]
    end

    def bot_enabled?
      result = ::PdrBot::Op::Bot::State.call
      handle_callback_failure(result[:error], __method__) unless result.success?
      @bot_enabled = result[:enabled]
      unless @bot_enabled
        PdrBot.logger.info "* Bot '#{PdrBot.app_name}' disabled.. Skip processing".bold.red
        throw :abort
      end
    end

    def with_locale(&block)
      # locale switching is not implemented
      I18n.with_locale(PdrBot.default_locale, &block)
    end
  end
end
