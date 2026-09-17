module ApplicationHelper
  def nav_class(active)
    base = "rounded px-2 py-1 "
    base + (active ? "bg-stone-900 text-white" : "text-stone-600 hover:bg-stone-100")
  end

  def flash_class(type)
    case type.to_s
    when "alert" then "border-red-200 bg-red-50 text-red-900"
    when "notice" then "border-emerald-200 bg-emerald-50 text-emerald-900"
    else "border-stone-200 bg-white text-stone-700"
    end
  end
end
