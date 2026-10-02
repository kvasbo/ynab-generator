require "time"

module YnabOfx
  class OfxWriter
    def self.render(statement)
      new(statement).render
    end

    def initialize(statement)
      @statement = statement
      @now = Time.now.utc
    end

    def render
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <?OFX OFXHEADER="200" VERSION="211" SECURITY="NONE" OLDFILEUID="NONE" NEWFILEUID="NONE"?>
        <OFX>
        #{signon}
        #{message_set}
        </OFX>
      XML
    end

    private

    attr_reader :statement

    def signon
      <<~XML.chomp
          <SIGNONMSGSRSV1>
            <SONRS>
              <STATUS>
                <CODE>0</CODE>
                <SEVERITY>INFO</SEVERITY>
              </STATUS>
              <DTSERVER>#{format_dt(@now)}</DTSERVER>
              <LANGUAGE>NOR</LANGUAGE>
            </SONRS>
          </SIGNONMSGSRSV1>
      XML
    end

    def message_set
      case statement.account_type
      when :bank       then bank_message_set
      when :creditcard then creditcard_message_set
      else raise ArgumentError, "unknown account type: #{statement.account_type.inspect}"
      end
    end

    def bank_message_set
      <<~XML.chomp
          <BANKMSGSRSV1>
            <STMTTRNRS>
              <TRNUID>1</TRNUID>
              <STATUS>
                <CODE>0</CODE>
                <SEVERITY>INFO</SEVERITY>
              </STATUS>
              <STMTRS>
                <CURDEF>#{statement.currency}</CURDEF>
                <BANKACCTFROM>
                  <BANKID>HANDNOKK</BANKID>
                  <ACCTID>#{escape(statement.account_id)}</ACCTID>
                  <ACCTTYPE>CHECKING</ACCTTYPE>
                </BANKACCTFROM>
        #{transaction_list}
        #{ledger_balance}
              </STMTRS>
            </STMTTRNRS>
          </BANKMSGSRSV1>
      XML
    end

    def creditcard_message_set
      <<~XML.chomp
          <CREDITCARDMSGSRSV1>
            <CCSTMTTRNRS>
              <TRNUID>1</TRNUID>
              <STATUS>
                <CODE>0</CODE>
                <SEVERITY>INFO</SEVERITY>
              </STATUS>
              <CCSTMTRS>
                <CURDEF>#{statement.currency}</CURDEF>
                <CCACCTFROM>
                  <ACCTID>#{escape(statement.account_id)}</ACCTID>
                </CCACCTFROM>
        #{transaction_list}
        #{ledger_balance}
              </CCSTMTRS>
            </CCSTMTTRNRS>
          </CREDITCARDMSGSRSV1>
      XML
    end

    def transaction_list
      txns = statement.transactions.map { |t| transaction(t) }.join("\n")
      <<~XML.chomp
                <BANKTRANLIST>
                  <DTSTART>#{format_dt(statement.start_date)}</DTSTART>
                  <DTEND>#{format_dt(statement.end_date)}</DTEND>
        #{txns}
                </BANKTRANLIST>
      XML
    end

    def transaction(t)
      <<~XML.chomp
                  <STMTTRN>
                    <TRNTYPE>#{t.trntype}</TRNTYPE>
                    <DTPOSTED>#{format_dt(t.date)}</DTPOSTED>
                    <TRNAMT>#{format_amount(t.amount)}</TRNAMT>
                    <FITID>#{escape(t.fitid)}</FITID>
                    <NAME>#{escape(t.payee)}</NAME>
                    <MEMO>#{escape(t.memo)}</MEMO>
                  </STMTTRN>
      XML
    end

    def ledger_balance
      return "" unless statement.balance
      <<~XML.chomp
                <LEDGERBAL>
                  <BALAMT>#{format_amount(statement.balance)}</BALAMT>
                  <DTASOF>#{format_dt(statement.balance_date || statement.end_date)}</DTASOF>
                </LEDGERBAL>
      XML
    end

    def format_dt(value)
      case value
      when Time     then value.strftime("%Y%m%d%H%M%S")
      when DateTime then value.strftime("%Y%m%d%H%M%S")
      when Date     then value.strftime("%Y%m%d")
      else raise ArgumentError, "cannot format #{value.inspect}"
      end
    end

    def format_amount(amount)
      sprintf("%.2f", amount)
    end

    def escape(str)
      str.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
    end
  end
end
