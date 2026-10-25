// Runtime adapter for the MIT V-Sekai PMX parser, embedded in the host's C API GDExtension.
using Pmx = mmd_pmx_t;
using PmxV3 = std::array<float, 3>;
using PmxV2 = std::array<float, 2>;
using PmxV4 = std::array<float, 4>;

int pmx_index(Pmx::sized_index_t* value) {
    if (!value) return -1;
    auto index = value->value();
    if ((value->size() == 1 && index == 255) || (value->size() == 2 && index == 65535) || index == 0xffffffffu) return -1;
    if (index > 0x7fffffffu) throw std::runtime_error("Invalid PMX signed index");
    return static_cast<int>(index);
}
Value pmx_numbers(PmxV3 value) {
    return Value::array({Value::number(value[0]), Value::number(value[1]), Value::number(value[2])});
}
Value pmx_numbers(PmxV4 value) {
    return Value::array({Value::number(value[0]), Value::number(value[1]), Value::number(value[2]), Value::number(value[3])});
}
PmxV3 pmx_vec(Pmx::vec3_t* value) { return {value->x(), value->y(), value->z()}; }
PmxV4 pmx_color(Pmx::color4_t* value) { return {value->r(), value->g(), value->b(), value->a()}; }
Value pmx_vectors(const std::vector<PmxV3>& data) {
    return Value::packed(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, gdabi::packed_vectors_size, data, api.vectors);
}
Value pmx_uvs(const std::vector<PmxV2>& data) {
    return Value::packed(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, gdabi::packed_uvs_size, data, api.uvs);
}
Value pmx_ints(const std::vector<int32_t>& data) {
    return Value::packed(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, gdabi::packed_ints_size, data, api.ints);
}
PmxV4 pmx_multiply(PmxV4 a, PmxV4 b) {
    return {a[3]*b[0]+a[0]*b[3]+a[1]*b[2]-a[2]*b[1], a[3]*b[1]-a[0]*b[2]+a[1]*b[3]+a[2]*b[0],
        a[3]*b[2]+a[0]*b[1]-a[1]*b[0]+a[2]*b[3], a[3]*b[3]-a[0]*b[0]-a[1]*b[1]-a[2]*b[2]};
}
PmxV4 pmx_rotation(Pmx::vec3_t* value) {
    // The same PMX YXZ frame as MMD, reflected into Godot's right-handed coordinates.
    float x = -value->x() * 0.5f, y = -value->y() * 0.5f, z = value->z() * 0.5f;
    return pmx_multiply(pmx_multiply({0, std::sin(y), 0, std::cos(y)}, {std::sin(x), 0, 0, std::cos(x)}), {0, 0, std::sin(z), std::cos(z)});
}

struct NativePmx {
    std::string error;
    Value read(const std::string& filename) {
        error.clear();
        auto path = std::filesystem::u8path(filename);
        auto size = std::filesystem::file_size(path);
        if (size < 33 || size > 128 * 1024 * 1024) throw std::runtime_error("PMX file exceeds the 128 MiB import limit");
        std::ifstream input(path, std::ios::binary);
        input.exceptions(std::ios::badbit | std::ios::failbit);
        kaitai::kstream stream(&input);
        Pmx model(&stream);
        if (model.vertex_count() < 3 || !model.bone_count() || !model.material_count()) throw std::runtime_error("PMX has no usable skinned mesh");
        const auto vertex_count = model.vertex_count();
        const auto bone_count = model.bone_count();
        std::vector<Value> warnings;
        std::vector<std::string> bone_names;
        std::vector<int> parents;
        std::unordered_set<std::string> used_names;
        for (uint32_t index = 0; index < bone_count; ++index) {
            auto* bone = model.bones()->at(index).get();
            auto name = bone->name()->value();
            for (char& c : name) if (c == ':' || c == '/' || c == '\\' || c == '.') c = '_';
            if (name.empty()) name = "Bone_" + std::to_string(index);
            while (!used_names.insert(name).second) name += "_" + std::to_string(index);
            bone_names.push_back(name);
            int parent = pmx_index(bone->parent_index());
            if (parent >= static_cast<int>(bone_count) || parent == static_cast<int>(index)) throw std::runtime_error("Invalid PMX bone parent");
            parents.push_back(parent);
        }
        for (uint32_t index = 0; index < bone_count; ++index) {
            int parent = parents[index];
            for (int depth = 0; parent >= 0; ++depth, parent = parents[parent])
                if (depth > 255 || parent == static_cast<int>(index)) throw std::runtime_error("Cyclic or excessively deep PMX skeleton");
        }
        for (const auto& face : *model.faces())
            for (const auto& index : *face->indices())
                if (index->value() >= vertex_count) throw std::runtime_error("PMX face index is out of range");

        uint64_t material_indices = 0;
        float lowest = std::numeric_limits<float>::max(), highest = std::numeric_limits<float>::lowest(), edge_max = 1;
        for (const auto& material : *model.materials()) {
            uint64_t count = material->face_vertex_count();
            if (count % 3 || material_indices + count > model.face_vertex_count()) throw std::runtime_error("Invalid PMX material face range");
            for (uint64_t index = material_indices / 3; material->diffuse()->a() > 0.001f && index < (material_indices + count) / 3; ++index)
                for (const auto& vertex : *model.faces()->at(index)->indices()) {
                    float y = model.vertices()->at(vertex->value())->position()->y();
                    lowest = std::min(lowest, y); highest = std::max(highest, y);
                }
            material_indices += count;
            for (auto texture : {material->texture_index(), material->sphere_texture_index()}) {
                int index = pmx_index(texture);
                if (index >= static_cast<int>(model.texture_count())) throw std::runtime_error("PMX texture index is out of range");
            }
            if (material->is_common_toon() > 1) throw std::runtime_error("Invalid PMX toon mode");
        }
        if (material_indices != model.face_vertex_count()) throw std::runtime_error("PMX material ranges do not cover the mesh");
        if (!(highest - lowest > 0.01f) || highest - lowest > 10000.f) throw std::runtime_error("PMX has no visible model or invalid dimensions");
        float unit = 1.7f / (highest - lowest);
        auto position = [&](Pmx::vec3_t* v) -> PmxV3 { return {v->x()*unit, (v->y()-lowest)*unit, -v->z()*unit}; };
        auto delta = [&](Pmx::vec3_t* v) -> PmxV3 { return {v->x()*unit, v->y()*unit, -v->z()*unit}; };

        std::vector<std::array<int32_t, 4>> bone_indices(vertex_count);
        std::vector<PmxV4> bone_weights(vertex_count);
        bool approximated_skin = false;
        for (uint32_t index = 0; index < vertex_count; ++index) {
            auto* vertex = model.vertices()->at(index).get();
            edge_max = std::max(edge_max, vertex->edge_ratio());
            auto& indices = bone_indices[index]; auto& weights = bone_weights[index];
            auto assign = [&](auto* data, int count) {
                for (int component = 0; component < count; ++component) indices[component] = pmx_index(data->bone_indices()->at(component).get());
            };
            switch (vertex->type()) {
                case Pmx::BONE_TYPE_BDEF1: indices[0] = pmx_index(static_cast<Pmx::bdef1_weights_t*>(vertex->skin_weights())->bone_index()); weights[0] = 1; break;
                case Pmx::BONE_TYPE_BDEF2: { auto* w = static_cast<Pmx::bdef2_weights_t*>(vertex->skin_weights()); assign(w, 2); weights[0] = w->weight1(); weights[1] = 1-weights[0]; break; }
                case Pmx::BONE_TYPE_SDEF: { auto* w = static_cast<Pmx::sdef_weights_t*>(vertex->skin_weights()); assign(w, 2); weights[0] = w->weight1(); weights[1] = 1-weights[0]; approximated_skin = true; break; }
                case Pmx::BONE_TYPE_BDEF4: { auto* w = static_cast<Pmx::bdef4_weights_t*>(vertex->skin_weights()); assign(w, 4); std::copy(w->weights()->begin(), w->weights()->end(), weights.begin()); break; }
                case Pmx::BONE_TYPE_QDEF: { auto* w = static_cast<Pmx::qdef_weights_t*>(vertex->skin_weights()); assign(w, 4); std::copy(w->weights()->begin(), w->weights()->end(), weights.begin()); approximated_skin = true; break; }
            }
            float total = 0;
            for (int component = 0; component < 4; ++component) {
                if (weights[component] < -0.0001f || weights[component] > 1.0001f) throw std::runtime_error("Invalid PMX bone weight");
                weights[component] = std::clamp(weights[component], 0.f, 1.f);
                if (weights[component] > 0 && (indices[component] < 0 || indices[component] >= static_cast<int>(bone_count))) throw std::runtime_error("PMX skin index is out of range");
                if (indices[component] < 0 || indices[component] >= static_cast<int>(bone_count)) indices[component] = 0;
                total += weights[component];
            }
            if (total < 0.000001f) { indices = {}; weights = {1, 0, 0, 0}; }
            else for (auto& weight : weights) weight /= total;
        }
        if (approximated_skin) warnings.push_back(Value::text("SDEF/QDEF 使用 Godot 线性蒙皮兼容模式。"));

        using Deltas = std::unordered_map<uint32_t, PmxV3>;
        std::vector<Deltas> resolved(model.morph_count());
        std::vector<int> visiting(model.morph_count());
        std::function<void(uint32_t)> resolve = [&](uint32_t index) {
            if (index >= model.morph_count() || visiting[index] == 1) throw std::runtime_error("Invalid or cyclic PMX group morph");
            if (visiting[index] == 2) return;
            visiting[index] = 1;
            auto* morph = model.morphs()->at(index).get();
            for (const auto& element : *morph->elements()) {
                if (morph->type() == Pmx::MORPH_TYPE_VERTEX) {
                    auto* value = static_cast<Pmx::vertex_morph_element_t*>(element.get());
                    auto vertex = value->index()->value();
                    if (vertex >= vertex_count) throw std::runtime_error("PMX morph vertex is out of range");
                    auto d = delta(value->position()); auto& target = resolved[index][vertex];
                    for (int component = 0; component < 3; ++component) target[component] += d[component];
                } else if (morph->type() == Pmx::MORPH_TYPE_GROUP || morph->type() == Pmx::MORPH_TYPE_FLIP) {
                    auto* value = static_cast<Pmx::group_morph_element_t*>(element.get());
                    int child = pmx_index(value->index());
                    if (child < 0) throw std::runtime_error("Invalid PMX group morph reference");
                    resolve(child);
                    for (const auto& item : resolved[child]) {
                        auto& target = resolved[index][item.first];
                        for (int component = 0; component < 3; ++component) {
                            target[component] += item.second[component] * value->ratio();
                            if (!std::isfinite(target[component])) throw std::runtime_error("PMX morph overflow");
                        }
                    }
                }
            }
            visiting[index] = 2;
        };
        std::vector<uint32_t> morph_indices;
        std::vector<Value> morph_names;
        used_names.clear();
        for (uint32_t index = 0; index < model.morph_count(); ++index) {
            resolve(index);
            if (resolved[index].empty()) continue;
            auto name = model.morphs()->at(index)->name()->value();
            if (name.empty()) name = "Morph_" + std::to_string(index);
            while (!used_names.insert(name).second) name += "_" + std::to_string(index);
            morph_indices.push_back(index); morph_names.push_back(Value::text(name));
        }
        if (static_cast<uint64_t>(vertex_count) * morph_names.size() > 12000000) throw std::runtime_error("PMX morph mesh exceeds real-time memory limits");
        std::vector<Value> textures, bones, names, materials, bodies, joints, surfaces;
        for (const auto& texture : *model.textures()) textures.push_back(Value::text(texture->name()->value()));
        for (uint32_t index = 0; index < bone_count; ++index) {
            bones.push_back(Value::dictionary({{"name", Value::text(bone_names[index])}, {"parent", Value::integer(parents[index])}, {"position", pmx_numbers(position(model.bones()->at(index)->position()))}}));
            names.push_back(Value::text(bone_names[index]));
        }
        uint32_t first_face = 0;
        uint64_t morph_vertex_total = 0;
        for (uint32_t material_index = 0; material_index < model.material_count(); ++material_index) {
            auto* material = model.materials()->at(material_index).get();
            auto id = "pmx_" + std::to_string(material_index) + "_" + material->name()->value();
            materials.push_back(Value::dictionary({{"name", Value::text(id)}, {"source_name", Value::text(material->name()->value())},
                {"source_index", Value::integer(material_index)}, {"base_color", pmx_numbers(pmx_color(material->diffuse()))},
                {"texture_index", Value::integer(pmx_index(material->texture_index()))}, {"sphere_texture_index", Value::integer(pmx_index(material->sphere_texture_index()))},
                {"sphere_mode", Value::integer(material->sphere_op_mode())}, {"edge_enabled", Value::boolean(material->outlined())},
                {"edge_color", pmx_numbers(pmx_color(material->edge_color()))}, {"edge_size", Value::number(material->edge_size())},
                {"double_sided", Value::boolean(material->no_cull())}, {"receive_shadow", Value::boolean(material->receive_shadow())},
                {"cast_shadow", Value::boolean(material->cast_shadow())}, {"vertex_color", Value::boolean(material->uses_vertex_color())}}));
            auto face_count = material->face_vertex_count() / 3;
            std::vector<int32_t> remap(vertex_count, -1), original, indices;
            for (uint32_t face = first_face; face < first_face + face_count; ++face)
                for (const auto& value : *model.faces()->at(face)->indices()) {
                    uint32_t index = value->value();
                    if (remap[index] < 0) { remap[index] = static_cast<int32_t>(original.size()); original.push_back(index); }
                    indices.push_back(remap[index]);
                }
            first_face += face_count;
            morph_vertex_total += static_cast<uint64_t>(original.size()) * morph_indices.size();
            if (morph_vertex_total > 12000000) throw std::runtime_error("Expanded PMX morph buffers exceed real-time memory limits");
            std::vector<PmxV3> positions, normals;
            std::vector<PmxV2> uvs;
            std::vector<PmxV4> colors;
            std::vector<int32_t> skin;
            std::vector<float> weights;
            std::vector<std::vector<float>> extras(model.header()->additional_uv_count());
            for (int32_t index : original) {
                auto* vertex = model.vertices()->at(index).get();
                positions.push_back(position(vertex->position()));
                auto normal = pmx_vec(vertex->normal()); normal[2] = -normal[2]; normals.push_back(normal);
                uvs.push_back({vertex->uv()->x(), vertex->uv()->y()});
                colors.push_back({1, 1, 1, std::max(0.f, vertex->edge_ratio()) / edge_max});
                skin.insert(skin.end(), bone_indices[index].begin(), bone_indices[index].end());
                weights.insert(weights.end(), bone_weights[index].begin(), bone_weights[index].end());
                for (uint8_t uv = 0; uv < extras.size(); ++uv) {
                    auto* v = vertex->additional_uvs()->at(uv).get();
                    extras[uv].insert(extras[uv].end(), {v->x(), v->y(), v->z(), v->w()});
                }
            }
            std::vector<Value> blend_shapes, extra_arrays;
            for (uint32_t morph : morph_indices) {
                std::vector<PmxV3> values(original.size());
                for (const auto& value : resolved[morph]) if (remap[value.first] >= 0) values[remap[value.first]] = value.second;
                blend_shapes.push_back(pmx_vectors(values));
            }
            for (const auto& extra : extras) extra_arrays.push_back(Value::floats(extra.data(), extra.size()));
            surfaces.push_back(Value::array({Value::integer(material_index), pmx_vectors(positions), pmx_vectors(normals), pmx_uvs(uvs),
                Value::packed(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, gdabi::packed_colors_size, colors, api.colors), pmx_ints(skin),
                Value::floats(weights.data(), weights.size()), pmx_ints(indices), Value::array(blend_shapes), Value::array(extra_arrays)}));
        }
        for (const auto& body : *model.rigid_bodies()) {
            int bone = pmx_index(body->bone_index());
            if (bone >= static_cast<int>(bone_count) || body->shape_type() > 2 || body->type() > 2 || body->group_index() > 15 || body->weight() < 0)
                throw std::runtime_error("Invalid PMX rigid body");
            PmxV3 dimensions = {body->width()*unit, body->height()*unit, body->depth()*unit};
            if (dimensions[0] < 0 || dimensions[1] < 0 || dimensions[2] < 0) throw std::runtime_error("Negative PMX rigid body size");
            if (body->shape_type() == 0) dimensions[1] = dimensions[2] = 0;
            if (body->shape_type() == 2) dimensions[2] = 0;
            bodies.push_back(Value::dictionary({{"name", Value::text(body->name()->value())}, {"bone", Value::text(bone >= 0 ? bone_names[bone] : "")},
                {"bone_index", Value::integer(bone)}, {"type", Value::integer(body->type())},
                {"shape", Value::text(body->shape_type() == 0 ? "sphere" : body->shape_type() == 1 ? "box" : "capsule")},
                {"size", pmx_numbers(dimensions)}, {"position", pmx_numbers(position(body->position()))}, {"rotation", pmx_numbers(pmx_rotation(body->rotation()))},
                {"mass", Value::number(body->weight())}, {"linear_damping", Value::number(body->position_damping())}, {"angular_damping", Value::number(body->rotation_damping())},
                {"restitution", Value::number(body->restitution())}, {"friction", Value::number(body->friction())}, {"collision_group", Value::integer(body->group_index())},
                {"collision_mask", Value::integer((~body->group_target()) & 65535)}, {"pmx_collision_mask", Value::integer(body->group_target())}}));
        }
        for (const auto& joint : *model.joints()) {
            int a = pmx_index(joint->rigid_body_indices()->at(0).get()), b = pmx_index(joint->rigid_body_indices()->at(1).get());
            if (a >= static_cast<int>(bodies.size()) || b >= static_cast<int>(bodies.size()) || joint->type() != Pmx::JOINT_TYPE_SPRING_SIXDOF)
                throw std::runtime_error("Unsupported PMX joint type or invalid body reference");
            auto lo = pmx_vec(joint->position_constraint_lower()), hi = pmx_vec(joint->position_constraint_upper());
            auto alo = pmx_vec(joint->rotation_constraint_lower()), ahi = pmx_vec(joint->rotation_constraint_upper());
            joints.push_back(Value::dictionary({{"name", Value::text(joint->name()->value())}, {"type", Value::integer(0)}, {"body_a", Value::integer(a)}, {"body_b", Value::integer(b)},
                {"position", pmx_numbers(position(joint->position()))}, {"rotation", pmx_numbers(pmx_rotation(joint->rotation()))},
                {"linear_lower", pmx_numbers(PmxV3{lo[0]*unit, lo[1]*unit, -hi[2]*unit})}, {"linear_upper", pmx_numbers(PmxV3{hi[0]*unit, hi[1]*unit, -lo[2]*unit})},
                {"angular_lower", pmx_numbers(PmxV3{-ahi[0], -ahi[1], alo[2]})}, {"angular_upper", pmx_numbers(PmxV3{-alo[0], -alo[1], ahi[2]})},
                {"spring_linear", pmx_numbers(pmx_vec(joint->spring_position()))}, {"spring_angular", pmx_numbers(pmx_vec(joint->spring_rotation()))}}));
        }
        std::string head;
        for (const auto& name : bone_names) if (name == "頭" || name == "head" || name == "Head") { head = name; break; }
        Value metadata = Value::dictionary({{"name", Value::text(model.header()->model_name()->value())}, {"loader", Value::text("native_pmx_v1")},
            {"model_comment", Value::text(model.header()->comment()->value())}, {"height", Value::number(1.7)}, {"scale", Value::number(unit)},
            {"triangle_count", Value::integer(model.face_vertex_count()/3)}, {"additional_uv_channels", Value::integer(model.header()->additional_uv_count())},
            {"bones", Value::array(names)}, {"morphs", Value::array(morph_names)}, {"materials", Value::array(materials)}, {"warnings", Value::array(warnings)},
            {"vertex_edge_weights", Value::boolean(true)}, {"vertex_edge_scale", Value::number(edge_max)},
            {"head", Value::dictionary({{"bone", Value::text(head)}, {"half_width", Value::number(0.08)}, {"nose_height", Value::number(0.025)}})},
            {"physics", Value::dictionary({{"version", Value::integer(1)}, {"coordinate_space", Value::text("normalized_model")}, {"unit_scale", Value::number(unit)},
                {"gravity", pmx_numbers(PmxV3{0,-9.8f,0})}, {"rigid_bodies", Value::array(bodies)}, {"joints", Value::array(joints)}})}});
        return Value::dictionary({{"metadata", metadata}, {"bones", Value::array(bones)}, {"textures", Value::array(textures)},
            {"morph_names", Value::array(morph_names)}, {"surfaces", Value::array(surfaces)}});
    }
};
