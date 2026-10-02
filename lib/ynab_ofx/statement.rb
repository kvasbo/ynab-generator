module YnabOfx
  Statement = Struct.new(
    :account_id,
    :account_name,
    :account_type,
    :currency,
    :transactions,
    :balance,
    :balance_date,
    :start_date,
    :end_date,
    keyword_init: true
  )
end
