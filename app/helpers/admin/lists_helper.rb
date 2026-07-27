module Admin
  module ListsHelper
    def avatar_tint(name)
      AvatarTint.index_for(name)
    end

    def format_phone(digits)
      PhoneFormat.call(digits)
    end

    def batch_period(batch)
      from = batch.period_from
      to = batch.period_to
      return t("admin.production_report.report.all_periods") unless from || to

      [ from, to ].compact.map { |date| l(date) }.join(" a ")
    end

    def period_label(from, to)
      return l(from, format: :list) unless to

      "#{l(from, format: :list)} – #{l(to, format: :list)}"
    end

    def status_trigger_label(statuses)
      case statuses.size
      when 0 then t("admin.dashboard.orders.filters.status_all")
      when 1 then t("account.orders.states.#{statuses.first}.label")
      else t("admin.lists.statuses_selected")
      end
    end

    def list_path(base_params, overrides = {})
      query = base_params.merge(overrides).compact_blank.to_query
      query.present? ? "#{request.path}?#{query}" : request.path
    end

    def page_path(base_params, number)
      list_path(base_params, page: (number if number > 1))
    end

    def page_range(page, one, many)
      noun = page.total == 1 ? one : many
      return safe_join([ tag.b(page.total), " #{noun}" ]) if page.total <= Admin::Page::PER

      safe_join([ tag.b("#{page.from}–#{page.to}"), " de ", tag.b(page.total), " #{noun}" ])
    end

    def sort_header(base_params, key:, label:, sort:, dir:, default_dir: "desc", extra_class: nil)
      column = Admin::ColumnSort.new(key: key, sort: sort, direction: dir, default_direction: default_dir)
      classes = [ "sortable", ("sorted" if column.active?), extra_class ].compact

      tag.th(class: classes.join(" ")) do
        link_to list_path(base_params, sort: key, dir: column.next_direction, page: nil) do
          safe_join([ label, tag.span(column.arrow, class: "sortarrow") ], " ")
        end
      end
    end
  end
end
