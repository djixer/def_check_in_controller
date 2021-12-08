class OrdersController < ApplicationController
  before_action :require_login, only: [:check]
  before_action :set_user, only: [:check]
  
  def check
    response = {}
    response[:balance] = @user.balance

    cpu = params[:cpu].to_i
    ram = params[:ram].to_i
    hdd_type = params[:hdd_type]
    hdd_capacity = params[:hdd_capacity].to_i
    os = params[:os]

    #Считаем стоимость выбранной конфигурации:
    response[:total] = get_price_vm(cpu, ram, hdd_type, hdd_capacity)

    #Проверка, что в сессии есть пользователь и его баланс:
    unless @user && @user.balance
      response[:result] = false
      response[:error] = 'В сессии нет имени пользователя или баланса.'
      render json: response, status: :unauthorized
      return
    end

    #Если не получили список доступных конфигураций:
    if get_list_configuration_vm.class != Hash
      response[:result] = false
      response[:error] = 'Не удалось получить список доступных конфигураций ВМ.'
      render json: response.except(:balance, :total), status: :service_unavailable
      return
    end

    #Если если выбранная пользователем конфигурация не соответствует ни одной доступной конфигурации:
    if is_configuration_valid?(cpu, ram, hdd_type, hdd_capacity, os) == false
      response[:result] = false
      response[:error] = 'Выбранная конфигурация не совпадает с доступными.'
      render json: response.except(:balance, :total), status: :not_acceptable
      return
    end

    #Если пользователю не хватает средств для оплаты выбранной конфигурации:
    if response[:total] > response[:balance]
      response[:result] = false
      response[:error] = 'Недостаточно средств.'
      render json: response.except(:balance, :total), status: :not_acceptable
      return
    end

    response[:result] = true
    response[:balance_after_transaction] = response[:balance] - response[:total]
    render json: response, status: :ok
  end

  private

  require 'net/http'

  def set_user
    @user = User.find_by(first_name: session[:login])
  end

  def require_login
    unless session[:login].present?
      redirect_to :login, notice: 'Метод доступен только для аутентифицированных пользователей.'
    end
  end

  #Получение от стороннего сервиса списка доступных конфигураций виртуальных машин:
  def get_list_configuration_vm
    url = 'http://possible_orders.srv.w55.ru/'
    uri = URI(url)
    response = Net::HTTP.get_response(uri)
    JSON.parse(response.body)
  rescue StandardError
  end

  #Проверяем, соответствует ли выбранная пользователем конфигурация, одной из доступных конфигураций:
  def is_configuration_valid?(cpu, ram, hdd_type, hdd_capacity, os)
    get_list_configuration_vm['specs'].each do |configuration|
      if configuration['os'].include?(os) &&
         configuration['cpu'].include?(cpu) &&
         configuration['ram'].include?(ram) &&
         configuration['hdd_type'].include?(hdd_type) &&
         (configuration['hdd_capacity'][hdd_type]['from']..configuration['hdd_capacity'][hdd_type]['to']).include?(hdd_capacity)
        return true
      end
    end
    false
  end

  #Получаем из другого нашего сервиса стоимость выбранной пользователем конфигурации:
  def get_price_vm(cpu, ram, hdd_type, hdd_capacity)
    url = "http://192.168.0.6:5678/cost?cpu=#{cpu}&ram=#{ram}&hdd_type=#{hdd_type}&hdd_capacity=#{hdd_capacity}"
    uri = URI(url)
    response = Net::HTTP.get_response(uri)
    response.body.to_i
  rescue StandardError
  end
end
