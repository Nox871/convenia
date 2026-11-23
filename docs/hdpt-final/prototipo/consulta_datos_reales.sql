select distinct on (pm.product_id, sp.supermarket_id) pm.product_id pid, sm.name tienda, po.price, po.observed_at::date f, sp.image_url, sp.name_raw
from source_products sp join product_matches pm on pm.source_product_id=sp.id and pm.status='CONFIRMED'
join supermarkets sm on sm.id=sp.supermarket_id
join price_observations po on po.source_product_id=sp.id and po.available
where sp.is_active and pm.product_id in (10953,11113,10971,10416,11332)
order by pm.product_id, sp.supermarket_id, po.observed_at desc;
